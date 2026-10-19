// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import Foundation
import HyperBufKit
import HyperBufProtocol
import WebKit

/// The state of one frame (a macOS window). Holds file access, file watching and the exchange with the Web core.
/// Each frame is an independent workspace (its own buffers, history and splits live in the Web core). docs/dev/buffer-model.md §7.
@MainActor
final class FrameSession: Identifiable {
    let id = UUID()
    /// Slot number (1-9). Corresponds to `Cmd-1` ... `Cmd-9` and does not change when the frame is closed.
    let slot: Int
    let access: FileAccess
    let editorConfig: EditorConfig
    /// The session to restore (passed to the Web core's `loadSession`).
    let initialSnapshot: Any?
    /// The last session saved by the Web core (the host writes all frames together).
    private(set) var lastSnapshot: Any?
    weak var webView: WKWebView?
    weak var window: NSWindow?
    private var watcher: FileWatcher?
    private var pageReady = false
    /// Paths proposed by the app that may be remembered (remembered only when approved; the Web side cannot add an arbitrary path).
    private var proposals: Set<String> = []
    /// "Open" requests that arrived before the Web core was ready. Handed over in order once it is.
    private var pendingOpens: [[String: Any]] = []

    /// Judgment for opening document links in the browser (`trustedUrls`, remembered sites). Shared by all frames.
    let urlPolicy: UrlPolicy
    let rememberedSites: RememberedOrigins
    /// URLs answered as needing confirmation (proposed by the app). After the confirmation, "open" and "remember" accept only these.
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

    // MARK: Web core readiness

    /// The Web core called `ready` (`onOpen` etc. are registered).
    func pageDidBecomeReady() {
        pageReady = true
        let items = pendingOpens
        pendingOpens.removeAll()
        for item in items { evaluateOpen(item) }
    }

    /// Passes to the Web core's `onOpen`. Held until it is ready if it is not yet.
    func deliverOpen(_ instruction: [String: Any]) {
        if pageReady { evaluateOpen(instruction) } else { pendingOpens.append(instruction) }
    }

    // MARK: Session

    func didSave(_ snapshot: Any) { lastSnapshot = snapshot }

    /// Has the session saved right now (just before quitting). Waits until the Web core finishes saving or `timeout` seconds pass.
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

    // MARK: Access judgment and remembering

    /// Judgment of the file a link or resource points to (the Web core's `checkAccess`). Nonexistent files are allow (reading fails later).
    func judge(_ path: String) -> [String: Any] {
        guard let decision = try? access.decide(path) else { return ["access": "allow"] }
        switch decision {
        case .allow: return ["access": "allow"]
        case .confirm(let remember):
            proposals.insert(remember)
            return ["access": "confirm", "remember": remember]
        }
    }

    /// Remembers an approved proposal. Paths that were not proposed are not remembered.
    func acceptProposal(_ remember: String) -> Bool {
        guard proposals.remove(remember) != nil else { return false }
        return access.remembered.add(remember)
    }

    // MARK: External URLs (open in the browser)

    /// Judgment of a document link (the Web core's `checkUrl`). Those needing confirmation are kept as proposals.
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

    /// Opens in the default browser. The judgment is made again here (the Web core's judgment is not trusted).
    func openExternal(_ url: String) -> Bool {
        switch urlPolicy.decide(url, remembered: rememberedSites) {
        case .deny: return false
        case .open: break
        case .confirm: guard urlProposals.remove(url) != nil else { return false }
        }
        guard let target = URL(string: url) else { return false }
        #if DEBUG
            // For tests: does not actually open; appends the URL to a log (so integration tests do not open a browser)
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

    /// "always": remembers that site (origin). Only the origin of a URL answered as needing confirmation.
    func rememberSite(_ url: String) -> Bool {
        guard urlProposals.contains(url), let origin = UrlPolicy.origin(of: url) else { return false }
        return rememberedSites.add(origin: origin)
    }

    // MARK: File watching

    /// The files on display (the Web core's `watch`). Only these are watched.
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

    // MARK: Calls into the Web core

    /// "Edit in editor" was chosen (context menu). The Web core asks for the location pointed at.
    func requestEdit() {
        guard pageReady else { return }
        webView?.evaluateJavaScript("window.__hostEdit && window.__hostEdit()")
    }

    /// Passes the id of a cancelled request to the Web core's `onOpenCancel` (closes the minibuffer waiting for confirmation).
    func cancelOpen(_ id: String) {
        guard pageReady, let json = Self.json(id) else { return }
        webView?.evaluateJavaScript("window.__hostOpenCancel && window.__hostOpenCancel(\(json))")
    }

    /// Has a command (`find-file` etc.) run. From the menu.
    func runCommand(_ name: String) {
        guard pageReady, let json = Self.json(name) else { return }
        webView?.evaluateJavaScript(
            "window.__hyperbuf && window.__hyperbuf.commands[\(json)] && window.__hyperbuf.commands[\(json)]()")
    }

    /// Queries the Web core's `onQuery`. null if it is not ready yet.
    func query(_ op: String) async -> JSONValue {
        guard pageReady, let webView else { return .null }
        let script = "return window.__hostQuery ? await window.__hostQuery(op) : null"
        let value = try? await webView.callAsyncJavaScript(
            script, arguments: ["op": op], in: nil, contentWorld: .page)
        return value.map { JSONValue(any: $0) } ?? .null
    }

    /// The current view (`get-view`). Paths are absolute paths.
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
