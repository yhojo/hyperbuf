// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import Foundation
import HyperBufKit
import HyperBufProtocol
import WebKit

/// 1 つのフレーム(macOS のウィンドウ)の状態。ファイルアクセス、ファイルの監視、Web コアとのやり取りを持つ。
/// 各フレームは、独立した作業場(自分のバッファ・履歴・分割を、Web コアの中に持つ)。docs/dev/buffer-model.md §7。
@MainActor
final class FrameSession: Identifiable {
    let id = UUID()
    /// スロット番号(1〜9)。`Cmd-1` … `Cmd-9` に対応し、フレームを閉じても変わらない。
    let slot: Int
    let access: FileAccess
    let editorConfig: EditorConfig
    /// 復元するセッション(Web コアの `loadSession` に渡す)。
    let initialSnapshot: Any?
    /// 最後に保存された、Web コアのセッション(ホストが、全フレームをまとめて書く)。
    private(set) var lastSnapshot: Any?
    weak var webView: WKWebView?
    weak var window: NSWindow?
    private var watcher: FileWatcher?
    private var pageReady = false
    /// アプリが提案した、記憶してよいパス(承認されたときだけ記憶する。Web 側から、任意のパスは足せない)。
    private var proposals: Set<String> = []
    /// Web コアの準備前に届いた「開く」要求。準備ができたら、順に渡す。
    private var pendingOpens: [[String: Any]] = []

    /// 文書のリンクをブラウザで開く判定(`trustedUrls`・記憶したサイト)。全フレームで共有する。
    let urlPolicy: UrlPolicy
    let rememberedSites: RememberedOrigins
    /// 確認が要ると答えた URL(アプリが提案したもの)。確認に答えたあとの「開く」「記憶」は、ここにあるものだけ受け付ける。
    private var urlProposals: Set<String> = []

    init(
        slot: Int, access: FileAccess, editorConfig: EditorConfig, snapshot: Any?, urlPolicy: UrlPolicy,
        rememberedSites: RememberedOrigins
    ) {
        self.slot = slot
        self.access = access
        self.editorConfig = editorConfig
        self.urlPolicy = urlPolicy
        self.rememberedSites = rememberedSites
        initialSnapshot = snapshot
        lastSnapshot = snapshot
        watcher = FileWatcher { [weak self] path, state in
            MainActor.assumeIsolated { self?.notifyChanged(path, state) }
        }
    }

    // MARK: Web コアの準備

    /// Web コアが `ready` を呼んだ(`onOpen` などの登録が済んだ)。
    func pageDidBecomeReady() {
        pageReady = true
        let items = pendingOpens
        pendingOpens.removeAll()
        for item in items { evaluateOpen(item) }
    }

    /// Web コアの `onOpen` に渡す。準備前なら、準備ができるまで保留する。
    func deliverOpen(_ instruction: [String: Any]) {
        if pageReady { evaluateOpen(instruction) } else { pendingOpens.append(instruction) }
    }

    // MARK: セッション

    func didSave(_ snapshot: Any) { lastSnapshot = snapshot }

    /// セッションを、いますぐ保存させる(終了の直前)。Web コアの保存が終わるか、`timeout` 秒たつまで待つ。
    func flushSession(timeout: Double = 1.5) async {
        guard pageReady, let webView else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish: @MainActor () -> Void = {
                if !resumed {
                    resumed = true
                    continuation.resume()
                }
            }
            Task { @MainActor in
                _ = try? await webView.callAsyncJavaScript(
                    "await (window.__hyperbuf && window.__hyperbuf.flushSession ? window.__hyperbuf.flushSession() : null); return true;",
                    contentWorld: .page)
                finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                finish()
            }
        }
    }

    // MARK: アクセス判定と記憶

    /// リンクやリソースが指すファイルの判定(Web コアの `checkAccess`)。存在しないものは allow(読むときに失敗する)。
    func judge(_ path: String) -> [String: Any] {
        guard let decision = try? access.decide(path) else { return ["access": "allow"] }
        switch decision {
        case .allow: return ["access": "allow"]
        case .confirm(let remember):
            proposals.insert(remember)
            return ["access": "confirm", "remember": remember]
        }
    }

    /// 承認された提案を、記憶する。提案していないパスは、記憶しない。
    func acceptProposal(_ remember: String) -> Bool {
        guard proposals.remove(remember) != nil else { return false }
        return access.remembered.add(remember)
    }

    // MARK: 外部の URL(ブラウザで開く)

    /// 文書のリンクの判定(Web コアの `checkUrl`)。確認が要るものは、提案として覚える。
    func judgeUrl(_ url: String) -> [String: Any] {
        switch urlPolicy.decide(url, remembered: rememberedSites) {
        case .open: return ["action": "open"]
        case .confirm(let origin):
            urlProposals.insert(url)
            var out: [String: Any] = ["action": "confirm"]
            if let origin { out["origin"] = origin }
            return out
        case .deny(let reason): return ["action": "deny", "reason": reason]
        }
    }

    /// 既定のブラウザで開く。判定を、ここでもう一度行う(Web コアの判断を信用しない)。
    func openExternal(_ url: String) -> Bool {
        switch urlPolicy.decide(url, remembered: rememberedSites) {
        case .deny: return false
        case .open: break
        case .confirm: guard urlProposals.remove(url) != nil else { return false }
        }
        guard let target = URL(string: url) else { return false }
        #if DEBUG
            // テスト用: 実際には開かず、ログに URL を追記する(統合テストが、ブラウザを開かないように)
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_TEST_OPEN_LOG"] {
                let line = url + "\n"
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile()
                    handle.write(Data(line.utf8))
                    try? handle.close()
                } else {
                    try? line.write(toFile: path, atomically: true, encoding: .utf8)
                }
                return true
            }
        #endif
        return NSWorkspace.shared.open(target)
    }

    /// 「always」: そのサイト(オリジン)を記憶する。確認が要ると答えた URL のオリジンだけ。
    func rememberSite(_ url: String) -> Bool {
        guard urlProposals.contains(url), let origin = UrlPolicy.origin(of: url) else { return false }
        return rememberedSites.add(origin: origin)
    }

    // MARK: ファイルの監視

    /// 表示中のファイル(Web コアの `watch`)。これだけを監視する。
    func setWatched(_ paths: [String]) {
        var set = Set<String>()
        for path in paths {
            if let real = try? access.canonical(path) { set.insert(real) }
        }
        watcher?.setPaths(set)
    }

    private func notifyChanged(_ path: String, _ state: FileWatcher.State) {
        guard let json = Self.json(path) else { return }
        let name = state == .deleted ? "deleted" : "changed"
        webView?.evaluateJavaScript("window.__hostChanged && window.__hostChanged(\(json), \"\(name)\")")
    }

    // MARK: Web コアへの呼び出し

    /// 「エディタで編集」が選ばれた(右クリックメニュー)。指した場所は、Web コアが求める。
    func requestEdit() {
        guard pageReady else { return }
        webView?.evaluateJavaScript("window.__hostEdit && window.__hostEdit()")
    }

    /// Web コアの `onOpenCancel` に、取り消された要求の id を渡す(確認待ちのミニバッファを閉じる)。
    func cancelOpen(_ id: String) {
        guard pageReady, let json = Self.json(id) else { return }
        webView?.evaluateJavaScript("window.__hostOpenCancel && window.__hostOpenCancel(\(json))")
    }

    /// コマンド(`find-file` など)を実行させる。メニューから。
    func runCommand(_ name: String) {
        guard pageReady, let json = Self.json(name) else { return }
        webView?.evaluateJavaScript(
            "window.__hyperbuf && window.__hyperbuf.commands[\(json)] && window.__hyperbuf.commands[\(json)]()")
    }

    /// Web コアの `onQuery` に問い合わせる。準備前なら null。
    func query(_ op: String) async -> JSONValue {
        guard pageReady, let webView else { return .null }
        let script = "return window.__hostQuery ? await window.__hostQuery(op) : null"
        let value = try? await webView.callAsyncJavaScript(
            script, arguments: ["op": op], in: nil, contentWorld: .page)
        return value.map { JSONValue(any: $0) } ?? .null
    }

    /// いまの表示(`get-view`)。パスは、絶対パス。
    func view() async -> JSONValue {
        guard case .object(var view) = await query("get-view") else { return .null }
        if let path = view["path"]?.string, !path.hasPrefix("*") { view["absolutePath"] = .string(path) }
        return .object(view)
    }

    private func evaluateOpen(_ instruction: [String: Any]) {
        guard let json = Self.json(instruction) else { return }
        webView?.evaluateJavaScript("window.__hostOpen && window.__hostOpen(\(json))")
    }

    private static func json(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) || value is String else { return nil }
        if let string = value as? String {
            guard let data = try? JSONEncoder().encode(string) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
