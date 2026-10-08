import Foundation
import HyperBufKit
import HyperBufProtocol
import WebKit

/// 1 つのプロジェクトを開いている間の状態。ファイルアクセス、ファイル監視、Web コアとのやり取りを持つ。
@MainActor
final class ProjectSession: Identifiable {
    let id = UUID()
    let project: Project
    let fileAccess: FileAccess
    weak var webView: WKWebView?
    private var watcher: FSWatcher?
    private var pageReady = false
    /// 利用者が「エディタで編集」で指した位置(エディタが `get-location` で取りに来る)。
    private(set) var markedLocation: LocationPayload?
    let editorConfig: EditorConfig
    /// Web コアの準備前に届いた「開く」要求。準備ができたら、順に渡す。
    private var pendingOpens: [[String: Any]] = []

    init(project: Project, trusted: TrustedRoots, editorConfig: EditorConfig = EditorConfig.load()) {
        self.project = project
        self.editorConfig = editorConfig
        fileAccess = FileAccess(project: project, trusted: trusted)
        watcher = FSWatcher(root: project.root) { [weak self] paths in
            // FSWatcher は、メインキューで通知する
            MainActor.assumeIsolated {
                for path in paths { self?.notifyChanged(path) }
            }
        }
    }

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

    /// 「エディタで編集」が選ばれた(右クリックメニュー)。指した場所は、Web コアが求める。
    func requestEdit() {
        guard pageReady else { return }
        webView?.evaluateJavaScript("window.__hostEdit && window.__hostEdit()")
    }

    /// Web コアが求めた位置を記録し、設定されていれば、エディタを呼び出す。
    func markLocation(_ web: WebLocation) async -> [String: Any] {
        switch LocationBuilder.build(web, access: fileAccess) {
        case .failure(let error):
            return ["ok": false, "triggered": false, "message": error.message]
        case .success(let payload):
            markedLocation = payload
            guard editorConfig.command != nil else {
                return [
                    "ok": true, "triggered": false,
                    "message": "位置を記録しました(エディタで M-x hyperbuf-visit-location)",
                ]
            }
            switch await EditorCommand.run(editorConfig) {
            case .success:
                return ["ok": true, "triggered": true, "message": "\(editorConfig.name) を呼び出しました"]
            case .failure(let failure):
                return [
                    "ok": true, "triggered": false,
                    "message": "位置は記録しましたが、エディタを呼び出せませんでした(\(failure))",
                ]
            }
        }
    }

    /// Web コアの `onOpenCancel` に、取り消された要求の id を渡す(確認待ちのミニバッファを閉じる)。
    func cancelOpen(_ id: String) {
        guard pageReady, let json = Self.json(id) else { return }
        webView?.evaluateJavaScript("window.__hostOpenCancel && window.__hostOpenCancel(\(json))")
    }

    /// Web コアの `onQuery` に問い合わせる。準備前なら null。
    func query(_ op: String) async -> JSONValue {
        guard pageReady, let webView else { return .null }
        let script = "return window.__hostQuery ? await window.__hostQuery(op) : null"
        let value = try? await webView.callAsyncJavaScript(
            script, arguments: ["op": op], in: nil, contentWorld: .page)
        return value.map { JSONValue(any: $0) } ?? .null
    }

    /// いまの表示(`get-view`)。相対パスには、絶対パス(`absolutePath`)を添える。
    func view() async -> JSONValue {
        guard case .object(var view) = await query("get-view") else { return .null }
        if let path = view["path"]?.string, !path.hasPrefix("*"), let absolute = try? fileAccess.absolutePath(path) {
            view["absolutePath"] = .string(absolute)
        }
        return .object(view)
    }

    private func evaluateOpen(_ instruction: [String: Any]) {
        guard let json = Self.json(instruction) else { return }
        webView?.evaluateJavaScript("window.__hostOpen && window.__hostOpen(\(json))")
    }

    /// Web コアの `onFileChanged` に通知する。パスは JSON 文字列として渡す(注入を避ける)。
    private func notifyChanged(_ path: String) {
        guard let json = Self.json(path) else { return }
        webView?.evaluateJavaScript("window.__hostChanged && window.__hostChanged(\(json))")
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
