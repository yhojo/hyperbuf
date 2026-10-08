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
    /// Web コアの準備前に届いた「開く」要求。準備ができたら、順に渡す。
    private var pendingOpens: [[String: Any]] = []

    init(project: Project, trusted: TrustedRoots) {
        self.project = project
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

    /// Web コアの `onQuery` に問い合わせる(`get-location` など)。準備前なら null。
    func query(_ op: String) async -> JSONValue {
        guard pageReady, let webView else { return .null }
        let script = "return window.__hostQuery ? await window.__hostQuery(op) : null"
        let value = try? await webView.callAsyncJavaScript(
            script, arguments: ["op": op], in: nil, contentWorld: .page)
        return value.map { JSONValue(any: $0) } ?? .null
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
