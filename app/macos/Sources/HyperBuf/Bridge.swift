// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufKit
import HyperBufProtocol
import OSLog
import WebKit

/// The macOS implementation of the Web core's `window.hyperbufHost` (the contract in core/src/host.ts). One per frame.
/// All file access goes through `FileAccess` (allow paths / warn paths).
@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "host"
    private static let logger = Logger(subsystem: "com.yhojo.hyperbuf", category: "bridge")

    /// Injected when the page starts. Implements the contract's functions as messages to the native side.
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
                vcsBranch: (dir) => call({ op: "vcs-branch", path: dir }),
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
                activeBuffer: (path) => { call({ op: "active-buffer", path }); },
                watch: (paths) => { call({ op: "watch", paths }); },
                onFileChanged: (cb) => { changeListeners.push(cb); },
                // The shell judges on every load (an image under a warn path gets a 404)
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
    /// Handler run once the Web core is ready, for "open" requests etc. that arrived before it was. Used by the test harness.
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
            // The user settings the Web core uses (the Web core validates them)
            let settings = UserSettings.load()
            replyHandler(
                [
                    "keybindings": UserKeybindings.load(from: EditorConfig.configURL()),
                    "restoreSession": settings.restoreSession,
                    "mathUnescapeUnderscore": settings.mathUnescapeUnderscore,
                    "followUpdates": settings.followUpdates,
                    "modeLineVcsBranch": settings.modeLineVcsBranch,
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
            // Enumerate on another thread so thousands of files do not block the main thread
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
        case "active-buffer":
            // nil (JSON null) when there is no buffer; otherwise only an absolute path is accepted
            let path = body["path"] as? String
            frame.activeBufferChanged(path.flatMap { $0.hasPrefix("/") ? $0 : nil }, model: model)
            replyHandler(nil, nil)
        case "vcs-branch":
            guard let path = body["path"] as? String, path.hasPrefix("/") else {
                return replyHandler(nil, "bad request")
            }
            let ignore = UserSettings.load().projectIgnorePaths
            Task {
                let branch = await Task.detached { VCSBranch.read(from: path, home: home, ignore: ignore) }.value
                replyHandler(branch ?? NSNull(), nil)
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
            // Only what the app proposed can be approved. The Web side cannot make us remember an arbitrary path
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
        /// For integration tests: appends the Web core's diagnostic log to the file named by `HYPERBUF_TEST_LOG`.
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

    /// Returns only a short reason to the Web core, without leaking internals.
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
