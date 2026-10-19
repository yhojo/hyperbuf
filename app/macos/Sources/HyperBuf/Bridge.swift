// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufKit
import HyperBufProtocol
import OSLog
import WebKit

/// Web コアの `window.hyperbufHost`(core/src/host.ts の契約)の、macOS での実体。1 フレームに 1 つ。
/// ファイルアクセスは、すべて `FileAccess`(許可パス / 警告パス)を通る。
@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "host"
    private static let logger = Logger(subsystem: "com.yhojo.hyperbuf", category: "bridge")

    /// ページの開始時に注入する。契約の関数を、ネイティブへのメッセージとして実装する。
    static func script(home: String) -> String {
        let homeJSON = (try? String(data: JSONEncoder().encode(home), encoding: .utf8)) ?? "\"/\""
        return """
            (() => {
              const call = (message) => window.webkit.messageHandlers.\(handlerName).postMessage(message);
              const changeListeners = [];
              const openListeners = [];
              const cancelListeners = [];
              const editListeners = [];
              let queryListener = null;
              window.__hostChanged = (path, state) => changeListeners.forEach((cb) => cb(path, state));
              window.__hostOpen = (request) => openListeners.forEach((cb) => cb(request));
              window.__hostEdit = () => editListeners.forEach((cb) => cb());
              window.__hostOpenCancel = (id) => cancelListeners.forEach((cb) => cb(id));
              window.__hostQuery = (op) => (queryListener ? queryListener(op) : null);
              const encode = (path) => path.split("/").map(encodeURIComponent).join("/");
              window.hyperbufHost = {
                name: "macos",
                home: \(homeJSON),
                getConfig: () => call({ op: "config" }),
                loadSession: () => call({ op: "load-session" }),
                saveSession: (snapshot) => call({ op: "save-session", snapshot }),
                listDirectory: (dir, options = {}) => call({ op: "list-dir", path: dir, hidden: !!options.hidden }),
                listTree: (dir) => call({ op: "list-tree", path: dir }),
                projectRoot: (dir) => call({ op: "project-root", path: dir }),
                readFile: (path) => call({ op: "read", path }),
                checkAccess: (paths) => call({ op: "check-access", paths }),
                allow: (remember) => call({ op: "allow", remember }),
                listRemembered: () => call({ op: "list-remembered" }),
                forget: (path) => call({ op: "forget", path }),
                checkUrl: (url) => call({ op: "check-url", url }),
                openExternal: (url) => call({ op: "open-url", url }),
                rememberSite: (url) => call({ op: "remember-site", url }),
                listRememberedSites: () => call({ op: "list-sites" }),
                forgetSite: (origin) => call({ op: "forget-site", origin }),
                watch: (paths) => { call({ op: "watch", paths }); },
                onFileChanged: (cb) => { changeListeners.push(cb); },
                // 判定はシェルが、読み込みのたびに行う(警告パスの画像は、404 になる)
                resolveResource: (path) => "\(ContentSecurityPolicy.scheme)://file" + encode(path),
                search: (dir, query, options = {}) => call({ op: "search", path: dir, query, limit: options.limit }),
                onOpen: (cb) => { openListeners.push(cb); },
                onOpenCancel: (cb) => { cancelListeners.push(cb); },
                onQuery: (cb) => { queryListener = cb; },
                onEdit: (cb) => { editListeners.push(cb); },
                markLocation: (location) => call({ op: "mark-location", location }),
                respond: (id, result) => { call({ op: "respond", id, result }); },
                confirmOpen: (id, accepted) => call({ op: "confirm-open", id, accepted }),
                frame: (action) => call({ op: "frame", action }),
                ready: () => { call({ op: "ready" }); },
                log: (text) => { call({ op: "log", text }); },
              };
            })();
            """
    }

    private let frame: FrameSession
    private let model: AppModel
    /// Web コアの準備前に届いた「開く」要求などのために、準備ができたときの処理。テストハーネスが使う。
    var onReady: (() -> Void)?

    init(frame: FrameSession, model: AppModel) {
        self.frame = frame
        self.model = model
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
        let access = frame.access
        let home = access.home
        switch op {
        case "config":
            // 利用者の設定のうち、Web コアが使うもの(検証は、Web コアが行う)
            let settings = UserSettings.load()
            replyHandler(
                [
                    "keybindings": UserKeybindings.load(from: EditorConfig.configURL()),
                    "restoreSession": settings.restoreSession,
                    "mathUnescapeUnderscore": settings.mathUnescapeUnderscore,
                    "followUpdates": settings.followUpdates,
                    "problems": access.policy.problems + settings.problems,
                ], nil)
        case "load-session":
            replyHandler(frame.initialSnapshot ?? NSNull(), nil)
        case "save-session":
            guard let snapshot = body["snapshot"] else { return replyHandler(nil, "bad request") }
            replyHandler(nil, model.frameDidSave(frame, snapshot: snapshot) ? nil : "cannot save")
        case "list-dir":
            guard let path = body["path"] as? String, path.hasPrefix("/") else {
                return replyHandler(nil, "bad request")
            }
            let hidden = body["hidden"] as? Bool ?? false
            // 数千ファイルでもメインスレッドを塞がないよう、別のスレッドで列挙する
            Task {
                let listing = await Task.detached { DirectoryLister.list(path, hidden: hidden) }.value
                replyHandler(Bridge.listingJSON(listing), nil)
            }
        case "list-tree":
            guard let path = body["path"] as? String, path.hasPrefix("/") else {
                return replyHandler(nil, "bad request")
            }
            Task {
                let tree = await Task.detached { DirectoryLister.tree(path, home: home) }.value
                replyHandler(Bridge.treeJSON(tree), nil)
            }
        case "project-root":
            guard let path = body["path"] as? String, path.hasPrefix("/") else {
                return replyHandler(nil, "bad request")
            }
            let ignore = UserSettings.load().projectIgnorePaths
            Task {
                let root = await Task.detached { ProjectRoot.find(from: path, home: home, ignore: ignore) }.value
                replyHandler(root, nil)
            }
        case "read":
            guard let path = body["path"] as? String else { return replyHandler(nil, "bad request") }
            do {
                replyHandler(try access.readMarkdown(path), nil)
            } catch {
                replyHandler(nil, Bridge.describe(error))
            }
        case "check-access":
            guard let paths = body["paths"] as? [String] else { return replyHandler(nil, "bad request") }
            replyHandler(paths.map { frame.judge($0) }, nil)
        case "allow":
            // 承認できるのは、アプリが提案したものだけ。Web 側から、任意のパスは記憶させられない
            guard let remember = body["remember"] as? String else { return replyHandler(false, nil) }
            replyHandler(frame.acceptProposal(remember), nil)
        case "list-remembered":
            replyHandler(access.remembered.all, nil)
        case "forget":
            guard let path = body["path"] as? String else { return replyHandler(false, nil) }
            replyHandler(access.remembered.remove(path), nil)
        case "check-url":
            guard let url = body["url"] as? String else {
                return replyHandler(["action": "deny", "reason": "bad request"], nil)
            }
            replyHandler(frame.judgeUrl(url), nil)
        case "open-url":
            replyHandler(frame.openExternal(body["url"] as? String ?? ""), nil)
        case "remember-site":
            replyHandler(frame.rememberSite(body["url"] as? String ?? ""), nil)
        case "list-sites":
            replyHandler(frame.rememberedSites.all, nil)
        case "forget-site":
            replyHandler(frame.rememberedSites.remove(origin: body["origin"] as? String ?? ""), nil)
        case "watch":
            frame.setWatched((body["paths"] as? [String]) ?? [])
            replyHandler(nil, nil)
        case "search":
            guard let path = body["path"] as? String, path.hasPrefix("/"), let query = body["query"] as? String,
                !query.isEmpty
            else { return replyHandler(nil, "empty query") }
            let limit = body["limit"] as? Int ?? 200
            Task {
                let response = await Task.detached {
                    TreeSearch.search(dir: path, home: home, query: query, limit: limit)
                }.value
                replyHandler(Bridge.jsonObject(response), nil)
            }
        case "mark-location":
            guard let object = body["location"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                let web = try? JSONDecoder().decode(WebLocation.self, from: data)
            else {
                return replyHandler(["ok": false, "triggered": false, "message": "Cannot interpret the location"], nil)
            }
            Task { replyHandler(await model.markLocation(web, from: frame), nil) }
        case "respond":
            if let id = body["id"] as? String, let payload = body["result"] as? [String: Any] {
                model.openFlow.handleWebResponse(id: id, payload: payload)
            }
            replyHandler(nil, nil)
        case "confirm-open":
            let id = body["id"] as? String ?? ""
            replyHandler(model.openFlow.confirmOpen(id: id, accepted: body["accepted"] as? Bool ?? false), nil)
        case "frame":
            model.handleFrameAction(body["action"] as? String ?? "", from: frame)
            replyHandler(nil, nil)
        case "ready":
            frame.pageDidBecomeReady()
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
        switch error as? AccessError {
        case .invalidPath: "invalid path"
        case .notMarkdown: "not a markdown file"
        case .notFound: "not found"
        case .unsupportedResource: "unsupported resource"
        case .needsConfirmation: "needs confirmation"
        case .unreadable, .none: "cannot read"
        }
    }

    private static func listingJSON(_ listing: DirectoryLister.Listing) -> [String: Any] {
        var out: [String: Any] = [
            "entries": listing.entries.map { ["name": $0.name, "dir": $0.dir] },
            "truncated": listing.truncated,
        ]
        if let error = listing.error { out["error"] = error }
        return out
    }

    private static func treeJSON(_ tree: DirectoryLister.Tree) -> [String: Any] {
        var out: [String: Any] = ["files": tree.files, "truncated": tree.truncated]
        if let refused = tree.refused { out["refused"] = refused }
        if let error = tree.error { out["error"] = error }
        return out
    }

    private static func jsonObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
