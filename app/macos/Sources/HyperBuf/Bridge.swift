import Foundation
import HyperBufKit
import HyperBufProtocol
import OSLog
import WebKit

/// Web コアの `window.hyperbufHost`(core/src/host.ts の契約)の、macOS での実体。
/// ファイルアクセスは、すべて `FileAccess`(プロジェクト + 信頼するルート)を通る。
@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "host"
    private static let logger = Logger(subsystem: "dev.hyperbuf", category: "bridge")

    /// ページの開始時に注入する。契約の関数を、ネイティブへのメッセージとして実装する。
    static let script = """
        (() => {
          const call = (message) => window.webkit.messageHandlers.\(handlerName).postMessage(message);
          const changeListeners = [];
          const openListeners = [];
          const cancelListeners = [];
          const editListeners = [];
          let queryListener = null;
          window.__hostChanged = (path) => changeListeners.forEach((cb) => cb(path));
          window.__hostOpen = (request) => openListeners.forEach((cb) => cb(request));
          window.__hostEdit = () => editListeners.forEach((cb) => cb());
          window.__hostOpenCancel = (id) => cancelListeners.forEach((cb) => cb(id));
          window.__hostQuery = (op) => (queryListener ? queryListener(op) : null);
          const encode = (path) => path.split("/").map(encodeURIComponent).join("/");
          window.hyperbufHost = {
            name: "macos",
            getConfig: () => call({ op: "config" }),
            listFiles: () => call({ op: "list" }),
            readFile: (path) => call({ op: "read", path }),
            onFileChanged: (cb) => { changeListeners.push(cb); },
            // 絶対パス(信頼するルートの内側)と、プロジェクト内の相対パスで、配る場所が違う
            resolveResource: (path) =>
              path.startsWith("/")
                ? "\(ContentSecurityPolicy.scheme)://trusted" + encode(path)
                : "\(ContentSecurityPolicy.scheme)://project/" + encode(path),
            search: (query, options = {}) => call({ op: "search", query, limit: options.limit }),
            onOpen: (cb) => { openListeners.push(cb); },
            onOpenCancel: (cb) => { cancelListeners.push(cb); },
            onQuery: (cb) => { queryListener = cb; },
            onEdit: (cb) => { editListeners.push(cb); },
            markLocation: (location) => call({ op: "mark-location", location }),
            respond: (id, result) => { call({ op: "respond", id, result }); },
            confirmOutside: (id, accepted) => call({ op: "confirm-outside", id, accepted }),
            ready: () => { call({ op: "ready" }); },
            log: (text) => { call({ op: "log", text }); },
          };
        })();
        """

    private let session: ProjectSession
    private let openFlow: OpenFlow
    /// Web コアが起動を終えた(`ready`)ときの処理。テストハーネスが使う。
    var onReady: (() -> Void)?

    init(session: ProjectSession, openFlow: OpenFlow) {
        self.session = session
        self.openFlow = openFlow
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
        let access = session.fileAccess
        switch op {
        case "config":
            // 利用者の設定のうち、Web コアが使うもの(検証は、Web コアが行う)
            replyHandler(["keybindings": UserKeybindings.load(from: EditorConfig.configURL())], nil)
        case "list":
            // 数千ファイルでもメインスレッドを塞がないよう、別のスレッドで列挙する
            Task {
                let files = await Task.detached { project.markdownFiles() }.value
                replyHandler(files, nil)
            }
        case "read":
            guard let path = body["path"] as? String else { return replyHandler(nil, "bad request") }
            do {
                replyHandler(try access.readMarkdown(path), nil)
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
        case "mark-location":
            guard let object = body["location"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                let web = try? JSONDecoder().decode(WebLocation.self, from: data)
            else { return replyHandler(["ok": false, "triggered": false, "message": "位置を解釈できません"], nil) }
            Task { replyHandler(await session.markLocation(web), nil) }
        case "respond":
            if let id = body["id"] as? String, let payload = body["result"] as? [String: Any] {
                openFlow.handleWebResponse(id: id, payload: payload)
            }
            replyHandler(nil, nil)
        case "confirm-outside":
            let id = body["id"] as? String ?? ""
            replyHandler(openFlow.confirmOutside(id: id, accepted: body["accepted"] as? Bool ?? false), nil)
        case "ready":
            session.pageDidBecomeReady()
            onReady?()
            replyHandler(nil, nil)
        case "log":
            let text = body["text"] as? String ?? ""
            Bridge.logger.info("web: \(text, privacy: .public)")
            #if DEBUG
                Bridge.appendTestLog(text)
            #endif
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "unknown op")
        }
    }

    #if DEBUG
        /// 統合テスト用: `HYPERBUF_TEST_LOG` のファイルに、Web コアの診断ログを追記する。
        private static func appendTestLog(_ text: String) {
            guard let path = ProcessInfo.processInfo.environment["HYPERBUF_TEST_LOG"] else { return }
            let line = "\(Int(Date().timeIntervalSince1970 * 1000)) \(text)\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    #endif

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
