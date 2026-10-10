import AppKit
import HyperBufIPC
import HyperBufKit
import HyperBufProtocol
import SwiftUI

/// フレーム(macOS のウィンドウ)の一覧と、外部連携(ソケット・URL スキーム)。docs/project-model.md §10。
/// 各フレームは、独立した作業場(`FrameSession`: 自分のバッファ・履歴・分割を持つ)。
@MainActor
final class AppModel: NSObject, NSWindowDelegate {
    static let shared = AppModel()
    let web: StaticFiles?
    /// 許可パス / 警告パス(設定ファイル)。全フレームで共有する。
    let policy: PathPolicy
    /// 利用者が承認して記憶した場所(永続化される)。全フレームで共有する。
    let remembered: RememberedPaths
    let sessionStore: SessionStore
    let editorConfig: EditorConfig
    let openFlow = OpenFlow()
    private let socketPath: String
    private var server: SocketServer?
    private(set) var frames: [Int: FrameSession] = [:]
    private(set) var activeSlot = 1
    private let restoreEnabled: Bool
    /// 「エディタで編集」で記録した位置(どのフレームのものか)。エディタが `get-location` で取りに来る。
    private var marked: (slot: Int, payload: LocationPayload)?
    private var persistTask: Task<Void, Never>?
    private var closingForQuit = false

    /// 最後にアクティブだったフレーム(なければ、番号の小さいもの)。
    var activeFrame: FrameSession? { frames[activeSlot] ?? frames.values.min { $0.slot < $1.slot } }

    override private init() {
        web = WebRoot.locate().map(StaticFiles.init(root:))
        let home = NSHomeDirectory()
        #if DEBUG
            // テスト用: 利用者の実際のソケット・記憶したパスの保存先を汚さないよう、デバッグビルドだけ差し替えられる
            let env = ProcessInfo.processInfo.environment
            remembered = RememberedPaths(
                url: env["HYPERBUF_TRUSTED_ROOTS"].map { URL(fileURLWithPath: $0) } ?? RememberedPaths.standardURL())
            socketPath = env["HYPERBUF_SOCKET_PATH"] ?? SocketPath.standard()
        #else
            remembered = RememberedPaths()
            socketPath = SocketPath.standard()
        #endif
        policy = PathPolicy.load(from: EditorConfig.configURL(), home: home)
        sessionStore = SessionStore()
        editorConfig = EditorConfig.load()
        restoreEnabled = SessionSettings.restoreEnabled()
        super.init()
        openFlow.model = self
    }

    // MARK: 起動

    /// 起動: 前回のフレームを復元し(なければ、スロット 1 を 1 つ)、起動の引数のファイル(ディレクトリは
    /// `index.md`、なければ `README.md`)を開く。
    func start(arguments: [String]) {
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

    // MARK: フレーム

    /// フレームを作って、ウィンドウを出す。
    @discardableResult
    func makeFrame(slot: Int, snapshot: Any?, rect: [String: Double]?) -> FrameSession? {
        guard let web, (1...SessionStore.maxFrames).contains(slot), frames[slot] == nil else { return nil }
        let access = FileAccess(policy: policy, remembered: remembered)
        let frame = FrameSession(slot: slot, access: access, editorConfig: editorConfig, snapshot: snapshot)
        let window = NSWindow(
            contentRect: Geometry.fit(rect, cascadeIndex: frames.count),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: WebShell(frame: frame, web: web, model: self))
        window.minSize = NSSize(width: 600, height: 400)
        window.delegate = self
        window.isReleasedWhenClosed = false
        frame.window = window
        frames[slot] = frame
        activeSlot = slot
        updateTitles()
        window.makeKeyAndOrderFront(nil)
        schedulePersist()
        return frame
    }

    /// 空いている最小のスロットで、新しいフレームを作る。
    func newFrame() {
        guard let slot = (1...SessionStore.maxFrames).first(where: { frames[$0] == nil }) else {
            NSSound.beep()
            return
        }
        makeFrame(slot: slot, snapshot: nil, rect: nil)
    }

    /// `Cmd-<slot>`: そのフレームを前面に出す。なければ、その番号で新しいフレームを作る。
    func activate(slot: Int) {
        if let frame = frames[slot] {
            frame.window?.makeKeyAndOrderFront(nil)
        } else {
            makeFrame(slot: slot, snapshot: nil, rect: nil)
        }
    }

    /// Web コアの `C-x 5 …`(`host.frame`)。
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

    /// メニューから、アクティブなフレームでコマンドを実行する。
    func runCommand(_ name: String) { activeFrame?.runCommand(name) }

    private func updateTitles() {
        for frame in frames.values {
            frame.window?.title = frames.count > 1 ? "HyperBuf [\(frame.slot)]" : "HyperBuf"
        }
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let frame = frames.values.first(where: { $0.window === window })
        else { return }
        activeSlot = frame.slot
        schedulePersist()
    }

    func windowDidMove(_ notification: Notification) { schedulePersist() }
    func windowDidResize(_ notification: Notification) { schedulePersist() }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let frame = frames.values.first(where: { $0.window === window })
        else { return }
        // 最後の 1 つを閉じる(= 終了)ときは、そのフレームのセッションを残す。ほかのフレームを閉じたときは、破棄する
        if frames.count > 1 && !closingForQuit {
            frames[frame.slot] = nil
            if activeSlot == frame.slot { activeSlot = frames.keys.min() ?? 1 }
            updateTitles()
        } else {
            persistNow()
            // 最後のフレームを閉じる = 終了。SwiftUI の Settings シーンがあると、「最後のウィンドウを閉じたら終了」が
            // 働かないので、明示的に終了する(セッションは、終了の手順で保存される)。
            // GCD のメインキューのブロックの中で terminate すると、終了待ち(terminateLater)の入れ子の実行ループが、
            // 同じ(直列の)メインキューにある保存の Task を動かせず、固まる。実行ループ経由で呼ぶ
            if !closingForQuit {
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
            }
        }
        schedulePersist()
    }

    // MARK: セッションの保存

    /// フレームのセッションを受け取った(Web コアの遅延書き込み)。全フレームをまとめて、1 つのファイルに書く。
    func frameDidSave(_ frame: FrameSession, snapshot: Any) -> Bool {
        guard restoreEnabled else { return true }  // 無効のあいだは、保存しない
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

    /// 終了の直前: 全フレームのセッションを、Web コアから受け取って、保存する。
    func flushAll() async {
        closingForQuit = true
        let tasks = frames.values.map { frame in Task { @MainActor in await frame.flushSession() } }
        for task in tasks { await task.value }
        persistNow()
    }

    // MARK: エディタ連携

    /// Web コアが求めた位置を記録し、設定されていれば、エディタを呼び出す。
    func markLocation(_ web: WebLocation, from frame: FrameSession) async -> [String: Any] {
        switch LocationBuilder.build(web, access: frame.access) {
        case .failure(let error):
            return ["ok": false, "triggered": false, "message": error.message]
        case .success(let payload):
            marked = (frame.slot, payload)
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

    // MARK: 外部連携

    /// ソケットのサーバーを起動する。すでに別のインスタンスが起動していれば、このインスタンスは終了する。
    func startServer() {
        let server = SocketServer(path: socketPath) { [weak self] request, operation, reply in
            Task { @MainActor in self?.handle(request, operation, reply) }
        }
        do {
            try server.start()
            self.server = server
        } catch SocketServer.StartError.alreadyRunning {
            NSLog("HyperBuf: すでに起動しています(\(server.path))。終了します")
            NSApp.terminate(nil)
        } catch {
            NSLog("HyperBuf: ソケットを起動できません: \(error)")
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
            // 利用者が「エディタで編集」で指した位置(照合用の情報つき)。まだなければ null
            reply(.success(id: request.id, .object(["location": marked?.payload.json ?? .null])))
        case .getView:
            guard let frame = activeFrame else { return reply(.success(id: request.id, .object(["view": .null]))) }
            Task { @MainActor in
                reply(.success(id: request.id, .object(["view": await frame.view()])))
            }
        }
    }

    /// `hyperbuf://` の URL(起動と、外部リンクからの「開く」)。結果を返す相手はいない。
    /// URL は、Web ページなどからも起動できる(起点を特定できない)ので、許可パスにないファイルは確認する。
    func handle(url: URL) {
        switch OpenURL.parse(url) {
        case .success(let request) where request.op == RequestOperation.open.rawValue:
            openFlow.submit(request, reply: nil, viaURL: true)
        case .success:
            break  // ping: アプリを起動するだけ
        case .failure(let error):
            activeFrame?.deliverOpen(["id": UUID().uuidString, "path": "", "error": error.message])
        }
    }
}

/// 起動の引数(ファイル、ディレクトリ)の解釈。docs/project-model.md §3.1。
enum Launch {
    /// 開くファイルの絶対パス。ディレクトリは `index.md`、なければ `README.md`(どちらもなければ、何もしない)。
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

/// ウィンドウの位置と大きさ(セッションに保存する)。
enum Geometry {
    static let defaultSize = NSSize(width: 1000, height: 700)

    static func dictionary(_ rect: NSRect) -> [String: Double] {
        ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
    }

    /// 保存された位置と大きさを、いまの画面に収まるように補正する(画面が変わっていても、外に出ない)。
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
                // 大きさは画面に収め、位置は画面の内側に寄せる
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
        // `swift run` のように、アプリのバンドルなしで起動したときも、通常のアプリとして前面に出す
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let model = AppModel.shared
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
                    // Finder の「このアプリケーションで開く」・ドラッグ&ドロップ: ファイル、ディレクトリ
                    for path in Launch.targets(from: ["", url.path]) {
                        AppModel.shared.openFlow.submit(Request(op: .open, path: path), reply: nil)
                    }
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 画面の状態(フレーム・window の配置・履歴・閲覧位置)を、保存してから終わる
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

@main
struct HyperBufApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // フレームのウィンドウは、AppModel が AppKit で作る。SwiftUI のシーンは、メニューのためだけに置く
        Settings {
            Text("設定は config.json に書きます(docs/configuration.md)")
                .padding(24)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新しいフレーム") { AppModel.shared.newFrame() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("ファイルを開く…") { AppModel.shared.runCommand("find-file") }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("フレーム") {
                ForEach(1...SessionStore.maxFrames, id: \.self) { slot in
                    Button("フレーム \(slot)") { AppModel.shared.activate(slot: slot) }
                        .keyboardShortcut(KeyEquivalent(Character("\(slot)")), modifiers: .command)
                }
            }
        }
    }
}
