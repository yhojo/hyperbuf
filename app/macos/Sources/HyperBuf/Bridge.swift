import Foundation
import HyperBufKit
import OSLog
import WebKit

/// Web コアの `window.hyperbufHost`(core/src/host.ts の契約)の、macOS での実体。
/// 操作は、一覧・読み取り・検索・診断ログだけ。ファイルアクセスは、すべて `Project` を通る。
@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "host"
    private static let logger = Logger(subsystem: "dev.hyperbuf", category: "bridge")

    /// ページの開始時に注入する。契約の関数を、ネイティブへのメッセージとして実装する。
    static let script = """
        (() => {
          const call = (message) => window.webkit.messageHandlers.\(handlerName).postMessage(message);
          const listeners = [];
          window.__hostChanged = (path) => listeners.forEach((cb) => cb(path));
          window.hyperbufHost = {
            name: "macos",
            listFiles: () => call({ op: "list" }),
            readFile: (path) => call({ op: "read", path }),
            onFileChanged: (cb) => { listeners.push(cb); },
            resolveResource: (path) => "\(ContentSecurityPolicy.scheme)://project/" + path.split("/").map(encodeURIComponent).join("/"),
            search: (query, options = {}) => call({ op: "search", query, limit: options.limit }),
            ready: () => { call({ op: "ready" }); },
            log: (text) => { call({ op: "log", text }); },
          };
        })();
        """

    private let session: ProjectSession
    /// Web コアが起動を終えた(`ready`)ときの処理。テストハーネスが使う。
    var onReady: (() -> Void)?

    init(session: ProjectSession) {
        self.session = session
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "bad message")
            return
        }
        let project = session.project
        switch op {
        case "list":
            // 数千ファイルでもメインスレッドを塞がないよう、別のスレッドで列挙する
            Task {
                let files = await Task.detached { project.markdownFiles() }.value
                replyHandler(files, nil)
            }
        case "read":
            guard let path = body["path"] as? String else { return replyHandler(nil, "bad request") }
            do {
                replyHandler(try project.readMarkdown(path), nil)
            } catch {
                replyHandler(nil, Bridge.describe(error))
            }
        case "search":
            guard let query = body["query"] as? String, !query.isEmpty else { return replyHandler(nil, "empty query") }
            let limit = body["limit"] as? Int ?? 200
            Task {
                let response = await Task.detached { ProjectSearch.search(project, query: query, limit: limit) }.value
                replyHandler(Bridge.jsonObject(response), nil)
            }
        case "ready":
            onReady?()
            replyHandler(nil, nil)
        case "log":
            Bridge.logger.info("web: \(body["text"] as? String ?? "", privacy: .public)")
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "unknown op")
        }
    }

    /// Web コアには、内部の事情を漏らさず、短い理由だけを返す。
    private static func describe(_ error: Error) -> String {
        switch error as? ProjectError {
        case .outside: "outside the project"
        case .notMarkdown: "not a markdown file"
        case .notFound: "not found"
        case .unsupportedResource: "unsupported resource"
        case .unreadable, .none: "cannot read"
        }
    }

    private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
