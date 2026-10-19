// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import HyperBufIPC
import HyperBufKit
import HyperBufProtocol
import SwiftUI

/// The list of frames (macOS windows) and the external integration (socket, URL scheme). docs/dev/buffer-model.md §7.
/// Each frame is an independent workspace (`FrameSession`: has its own buffers, history and splits).
@MainActor
final class AppModel: NSObject, NSWindowDelegate {
    static let shared = AppModel()
    let web: StaticFiles?
    /// Allow paths / warn paths (config file). Shared by all frames.
    let policy: PathPolicy
    /// Places the user approved and remembered (persisted). Shared by all frames.
    let remembered: RememberedPaths
    let sessionStore: SessionStore
    let editorConfig: EditorConfig
    /// Judgment for opening document links in the browser. Shared by all frames.
    let urlPolicy: UrlPolicy
    let rememberedSites: RememberedOrigins
    let openFlow = OpenFlow()
    private let socketPath: String
    private var server: SocketServer?
    private(set) var frames: [Int: FrameSession] = [:]
    private(set) var activeSlot = 1
    /// The Window menu. The items of open frames (`Cmd-<slot>`) are listed here.
    weak var windowMenu: NSMenu?
    private let restoreEnabled: Bool
    /// The location recorded by "Edit in editor" (and which frame it is from). The editor fetches it with `get-location`.
    private var marked: (slot: Int, payload: LocationPayload)?
    private var persistTask: Task<Void, Never>?
    private var closingForQuit = false

    /// The last active frame (otherwise the one with the lowest number).
    var activeFrame: FrameSession? { frames[activeSlot] ?? frames.values.min { $0.slot < $1.slot } }

    override private init() {
        web = WebRoot.locate().map(StaticFiles.init(root:))
        let home = NSHomeDirectory()
        #if DEBUG
            // For tests: only debug builds can swap these, so the user's real socket and remembered-path store are not polluted
            let env = ProcessInfo.processInfo.environment
            remembered = RememberedPaths(
                url: env["HYPERBUF_TRUSTED_ROOTS"].map { URL(fileURLWithPath: $0) } ?? RememberedPaths.standardURL())
            rememberedSites = RememberedOrigins(
                url: env["HYPERBUF_TRUSTED_SITES"].map { URL(fileURLWithPath: $0) } ?? RememberedOrigins.standardURL())
            socketPath = env["HYPERBUF_SOCKET_PATH"] ?? SocketPath.standard()
        #else
            remembered = RememberedPaths()
            rememberedSites = RememberedOrigins()
            socketPath = SocketPath.standard()
        #endif
        policy = PathPolicy.load(from: EditorConfig.configURL(), home: home)
        urlPolicy = UrlPolicy(trusted: UserSettings.load().trustedUrls)
        sessionStore = SessionStore()
        editorConfig = EditorConfig.load()
        restoreEnabled = SessionSettings.restoreEnabled()
        super.init()
        openFlow.model = self
    }

    // MARK: Launch

    /// Launch: restores the previous frames (or one frame in slot 1 if none) and opens the file given as the launch argument (a directory
    /// opens `index.md`, else `README.md`).
    func start(arguments: [String]) {
        let settings = UserSettings.load()
        applyAppearance(settings.appearance)
        alpha = settings.alpha
        // Re-apply when "Reduce transparency" (accessibility) is toggled
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateAlpha() } }
        var restored = false
        if restoreEnabled, let stored = sessionStore.load(), let list = stored["frames"] as? [[String: Any]],
            !list.isEmpty
        {
            for item in list.sorted(by: { ($0["slot"] as? Int ?? 0) < ($1["slot"] as? Int ?? 0) }) {
                guard let slot = item["slot"] as? Int else { continue }
                makeFrame(slot: slot, snapshot: item["snapshot"], rect: item["rect"] as? [String: Double])
                restored = true
            }
            if let active = stored["active"] as? Int, frames[active] != nil { activeSlot = active }
        }
        if !restored { makeFrame(slot: 1, snapshot: nil, rect: nil) }
        frames[activeSlot]?.window?.makeKeyAndOrderFront(nil)
        openFlow.flushQueued()
        for path in Launch.targets(from: arguments) {
            openFlow.submit(Request(op: .open, path: path), reply: nil)
        }
    }

    // MARK: Frames

    /// Creates a frame and shows its window.
    @discardableResult
    func makeFrame(slot: Int, snapshot: Any?, rect: [String: Double]?) -> FrameSession? {
        guard let web, (1...SessionStore.maxFrames).contains(slot), frames[slot] == nil else { return nil }
        let access = FileAccess(policy: policy, remembered: remembered)
        let frame = FrameSession(
            slot: slot, access: access, editorConfig: editorConfig, snapshot: snapshot, urlPolicy: urlPolicy,
            rememberedSites: rememberedSites)
        let window = NSWindow(
            contentRect: Geometry.fit(rect, cascadeIndex: frames.count),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: WebShell(frame: frame, web: web, model: self))
        window.minSize = NSSize(width: 600, height: 400)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isRestorable = false  // macOS window restoration is not used (the session does the restoring)
        // The Window menu lists our own items with `Cmd-<slot>`, not AppKit's automatic list (so nothing is duplicated)
        window.isExcludedFromWindowsMenu = true
        frame.window = window
        frames[slot] = frame
        activeSlot = slot
        updateTitles()
        updateAlpha()
        window.makeKeyAndOrderFront(nil)
        schedulePersist()
        return frame
    }

    /// The frame's opacity (`alpha`). The value differs for the frontmost frame and the others.
    private var alpha = WindowAlpha.opaque

    /// Sets every frame's opacity to match the current state (whether it is frontmost).
    func updateAlpha() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        for frame in frames.values {
            guard let window = frame.window else { continue }
            window.alphaValue = alpha.value(isKey: window.isKeyWindow, reduceTransparency: reduce)
        }
    }

    /// Applies the appearance (`appearance`) app-wide. Windows, menus and the WebView's `prefers-color-scheme` follow it.
    /// For `system`, removes the override and follows the OS.
    func applyAppearance(_ appearance: Appearance) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Creates a new frame in the lowest free slot.
    func newFrame() {
        guard let slot = (1...SessionStore.maxFrames).first(where: { frames[$0] == nil }) else {
            NSSound.beep()
            return
        }
        makeFrame(slot: slot, snapshot: nil, rect: nil)
    }

    /// `Cmd-<slot>`: brings that frame to the front. Does nothing for a slot that is not open (new frames are made with `newFrame`).
    func activate(slot: Int) {
        frames[slot]?.window?.makeKeyAndOrderFront(nil)
    }

    /// The Web core's `C-x 5 ...` (`host.frame`).
    func handleFrameAction(_ action: String, from frame: FrameSession) {
        switch action {
        case "make": newFrame()
        case "delete": frame.window?.performClose(nil)
        case "other":
            let slots = frames.keys.sorted()
            guard let index = slots.firstIndex(of: frame.slot), slots.count > 1 else { return }
            activate(slot: slots[(index + 1) % slots.count])
        case "delete-others":
            for other in frames.values where other.slot != frame.slot { other.window?.performClose(nil) }
        default: break
        }
    }

    /// Runs a command in the active frame, from the menu.
    func runCommand(_ name: String) { activeFrame?.runCommand(name) }

    // MARK: Menu actions (from MainMenu)

    @objc func menuNewFrame(_ sender: Any?) { newFrame() }
    @objc func menuOpenFile(_ sender: Any?) { runCommand("find-file") }
    @objc func menuRevealConfig(_ sender: Any?) { ConfigLocation.reveal() }

    /// About: name, version and copyright (Info.plist), plus the license and where the third-party licenses are.
    @objc func menuAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string:
                "Apache License 2.0\n\nCopyright notices and licenses of third-party software are available from the menu: Show Third-Party Licenses.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Opens the bundled third-party licenses (`THIRD-PARTY-NOTICES.txt`) in the default app.
    @objc func menuShowNotices(_ sender: Any?) {
        if let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func menuActivateFrame(_ sender: NSMenuItem) { activate(slot: sender.tag) }

    private func updateTitles() {
        for frame in frames.values {
            frame.window?.title = frames.count > 1 ? "HyperBuf [\(frame.slot)]" : "HyperBuf"
        }
        refreshWindowMenu()
    }

    /// Rebuilds the frame items of the Window menu (open frames only; `Cmd-<slot>`, the frontmost is marked).
    /// The standard items (minimize, zoom, full screen) are left as they are.
    func refreshWindowMenu() {
        guard let menu = windowMenu else { return }
        for item in menu.items where item.tag > 0 { menu.removeItem(item) }
        let slots = frames.keys.sorted()
        guard !slots.isEmpty else { return }
        let separator = NSMenuItem.separator()
        separator.tag = slots[0]
        menu.addItem(separator)
        for slot in slots {
            let item = menu.addItem(
                withTitle: "HyperBuf [\(slot)]", action: #selector(menuActivateFrame(_:)), keyEquivalent: "\(slot)")
            item.target = self
            item.tag = slot
            item.state = slot == activeSlot ? .on : .off
        }
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let frame = frames.values.first(where: { $0.window === window })
        else { return }
        activeSlot = frame.slot
        refreshWindowMenu()
        updateAlpha()
        schedulePersist()
    }

    func windowDidResignKey(_ notification: Notification) { updateAlpha() }

    func windowDidMove(_ notification: Notification) { schedulePersist() }
    func windowDidResize(_ notification: Notification) { schedulePersist() }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let frame = frames.values.first(where: { $0.window === window })
        else { return }
        // When the last one is closed (= quit), keep that frame's session. When another frame is closed, discard it
        if frames.count > 1 && !closingForQuit {
            frames[frame.slot] = nil
            if activeSlot == frame.slot { activeSlot = frames.keys.min() ?? 1 }
            updateTitles()
        } else {
            persistNow()
            // Closing the last frame = quit. With a SwiftUI Settings scene, "quit after the last window closes"
            // does not work, so quit explicitly (the session is saved in the quit procedure).
            // Calling terminate inside a GCD main-queue block makes the nested run loop of the terminate wait (terminateLater)
            // unable to run the save Task on the same (serial) main queue, and it hangs. Call it via the run loop
            if !closingForQuit {
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
            }
        }
        schedulePersist()
    }

    // MARK: Saving the session

    /// Received a frame's session (the Web core's deferred write). Writes all frames together into one file.
    func frameDidSave(_ frame: FrameSession, snapshot: Any) -> Bool {
        guard restoreEnabled else { return true }  // Does not save while disabled
        frame.didSave(snapshot)
        schedulePersist()
        return true
    }

    private func schedulePersist() {
        guard restoreEnabled else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persistNow() {
        guard restoreEnabled, !frames.isEmpty else { return }
        persistTask?.cancel()
        var list: [[String: Any]] = []
        for frame in frames.values.sorted(by: { $0.slot < $1.slot }) {
            var item: [String: Any] = ["slot": frame.slot]
            if let window = frame.window { item["rect"] = Geometry.dictionary(window.frame) }
            if let snapshot = frame.lastSnapshot { item["snapshot"] = snapshot }
            list.append(item)
        }
        sessionStore.save(["version": 2, "active": activeSlot, "frames": list])
    }

    /// Just before quitting: receives every frame's session from the Web core and saves it.
    func flushAll() async {
        closingForQuit = true
        let tasks = frames.values.map { frame in Task { @MainActor in await frame.flushSession() } }
        for task in tasks { await task.value }
        persistNow()
    }

    // MARK: Editor integration

    /// Records the location the Web core asked for and, if configured, invokes the editor.
    func markLocation(_ web: WebLocation, from frame: FrameSession) async -> [String: Any] {
        switch LocationBuilder.build(web, access: frame.access) {
        case .failure(let error):
            return ["ok": false, "triggered": false, "message": error.message]
        case .success(let payload):
            marked = (frame.slot, payload)
            guard editorConfig.command != nil else {
                return [
                    "ok": true, "triggered": false,
                    "message": "Location recorded (run M-x hyperbuf-visit-location in the editor)",
                ]
            }
            switch await EditorCommand.run(editorConfig) {
            case .success:
                return ["ok": true, "triggered": true, "message": "Invoked \(editorConfig.name)"]
            case .failure(let failure):
                return [
                    "ok": true, "triggered": false,
                    "message": "Location recorded, but the editor could not be invoked (\(failure))",
                ]
            }
        }
    }

    // MARK: External integration

    /// Starts the socket server. If another instance is already running, this instance quits.
    func startServer() {
        let server = SocketServer(path: socketPath) { [weak self] request, operation, reply in
            Task { @MainActor in self?.handle(request, operation, reply) }
        }
        do {
            try server.start()
            self.server = server
        } catch SocketServer.StartError.alreadyRunning {
            NSLog("HyperBuf: already running (\(server.path)); exiting")
            NSApp.terminate(nil)
        } catch {
            NSLog("HyperBuf: cannot start socket: \(error)")
        }
    }

    func stopServer() { server?.stop() }

    private func handle(_ request: Request, _ operation: RequestOperation, _ reply: @escaping SocketServer.Reply) {
        switch operation {
        case .ping:
            reply(
                .success(
                    id: request.id,
                    .object([
                        "version": .string(hyperBufVersion),
                        "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)),
                        "protocol": .number(Double(HyperBufProtocol.version)),
                    ])))
        case .open:
            openFlow.submit(request, reply: reply)
        case .getLocation:
            // The location the user pointed at with "Edit in editor" (with information for verification). null if there is none yet
            reply(.success(id: request.id, .object(["location": marked?.payload.json ?? .null])))
        case .getView:
            guard let frame = activeFrame else { return reply(.success(id: request.id, .object(["view": .null]))) }
            Task { @MainActor in
                reply(.success(id: request.id, .object(["view": await frame.view()])))
            }
        }
    }

    /// A `hyperbuf://` URL (launch, and "open" from an external link). There is nobody to return the result to.
    /// A URL can also be triggered from a web page etc. (the origin cannot be identified), so files not under an allow path are confirmed.
    func handle(url: URL) {
        switch OpenURL.parse(url) {
        case .success(let request) where request.op == RequestOperation.open.rawValue:
            openFlow.submit(request, reply: nil, viaURL: true)
        case .success:
            break  // ping: just launches the app
        case .failure(let error):
            activeFrame?.deliverOpen(["id": UUID().uuidString, "path": "", "error": error.message])
        }
    }
}

/// Shows the location of the config file (`config.json`) in Finder. The app never rewrites the config file
/// (if it does not exist, shows the directory where it belongs).
enum ConfigLocation {
    @MainActor static func reveal() {
        let url = EditorConfig.configURL()
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

/// Interpretation of the launch arguments (file, directory). docs/dev/buffer-model.md §5.1.
enum Launch {
    /// Absolute path of the file to open. A directory gives `index.md`, else `README.md` (if neither exists, nothing happens).
    static func targets(from arguments: [String]) -> [String] {
        var out: [String] = []
        for argument in arguments.dropFirst() where !argument.hasPrefix("-") {
            let url = URL(fileURLWithPath: argument).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                for name in ["index.md", "README.md"] {
                    let candidate = url.appendingPathComponent(name).path
                    if FileManager.default.fileExists(atPath: candidate) {
                        out.append(candidate)
                        break
                    }
                }
            } else if url.pathExtension == "md" {
                out.append(url.path)
            }
        }
        return out
    }
}

/// A window's position and size (saved in the session).
enum Geometry {
    static let defaultSize = NSSize(width: 1000, height: 700)

    static func dictionary(_ rect: NSRect) -> [String: Double] {
        ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
    }

    /// Adjusts the saved position and size to fit the current screen (it stays on screen even if the screens changed).
    static func fit(_ saved: [String: Double]?, cascadeIndex: Int) -> NSRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallback = screens.first ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved, let x = saved["x"], let y = saved["y"], let w = saved["width"], let h = saved["height"],
            w >= 300, h >= 200, w <= 10000, h <= 10000
        {
            let rect = NSRect(x: x, y: y, width: w, height: h)
            if let screen = screens.first(where: {
                $0.intersection(rect).width >= 100 && $0.intersection(rect).height >= 50
            }) {
                // Fit the size to the screen and move the position inside it
                var fitted = rect
                fitted.size.width = min(fitted.width, screen.width)
                fitted.size.height = min(fitted.height, screen.height)
                fitted.origin.x = min(max(fitted.origin.x, screen.minX), screen.maxX - fitted.width)
                fitted.origin.y = min(max(fitted.origin.y, screen.minY), screen.maxY - fitted.height)
                return fitted
            }
        }
        let size = NSSize(
            width: min(defaultSize.width, fallback.width), height: min(defaultSize.height, fallback.height))
        let offset = CGFloat(cascadeIndex % 6) * 28
        return NSRect(
            x: fallback.minX + 60 + offset, y: fallback.maxY - size.height - 60 - offset, width: size.width,
            height: size.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Even when launched without an app bundle, like `swift run`, bring it to the front as a normal app
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let model = AppModel.shared
            MainMenu.install(model: model)
            model.startServer()
            model.start(arguments: CommandLine.arguments)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if url.scheme == "hyperbuf" {
                    AppModel.shared.handle(url: url)
                } else if url.isFileURL {
                    // Finder's "Open With" and drag & drop: files, directories
                    for path in Launch.targets(from: ["", url.path]) {
                        AppModel.shared.openFlow.submit(Request(op: .open, path: path), reply: nil)
                    }
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save the screen state (frames, window layout, history, reading positions), then finish
        Task { @MainActor in
            await AppModel.shared.flushAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stopServer() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
