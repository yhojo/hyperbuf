import AppKit
import HyperBufIPC
import HyperBufKit
import HyperBufProtocol
import SwiftUI

/// いま開いているプロジェクトと、外部連携(ソケット・URL スキーム)。切り替えると、WebView ごと作り直す。
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    var session: ProjectSession?
    let web: StaticFiles?
    /// 利用者が承認した、プロジェクト外の読んでよいディレクトリ(永続化される)。
    @ObservationIgnored let trusted: TrustedRoots
    @ObservationIgnored let openFlow = OpenFlow()
    @ObservationIgnored private let socketPath: String
    @ObservationIgnored private var server: SocketServer?
    @ObservationIgnored private var isSelectingProject = false

    private init() {
        web = WebRoot.locate().map(StaticFiles.init(root:))
        #if DEBUG
            // テスト用: 利用者の実際のソケット・信頼するルートの保存先を汚さないよう、デバッグビルドだけ差し替えられる
            let env = ProcessInfo.processInfo.environment
            trusted = TrustedRoots(
                url: env["HYPERBUF_TRUSTED_ROOTS"].map { URL(fileURLWithPath: $0) } ?? TrustedRoots.standardURL())
            socketPath = env["HYPERBUF_SOCKET_PATH"] ?? SocketPath.standard()
        #else
            trusted = TrustedRoots()
            socketPath = SocketPath.standard()
        #endif
        openFlow.model = self
    }

    // MARK: プロジェクト

    func open(_ project: Project) {
        openFlow.failAll(ProtocolError(.outsideProject, "プロジェクトが切り替わりました"))
        let session = ProjectSession(project: project, trusted: trusted)
        self.session = session
        openFlow.flushQueued(into: session)
    }

    /// メニューから、プロジェクトを選び直す。
    func chooseProject() {
        if let project = ProjectPicker.choose() { open(project) }
    }

    /// 外部の要求に応じて、プロジェクトを選んでもらう(選ばれなければ、待っている要求を失敗で終える)。
    func requestProjectSelection(startingAt: String?) {
        guard !isSelectingProject else { return }
        isSelectingProject = true
        Task { @MainActor in
            defer { isSelectingProject = false }
            if let project = ProjectPicker.choose(startingAt: startingAt) {
                open(project)
            } else if session == nil {
                openFlow.failAll(ProtocolError(.outsideProject, "プロジェクトが選ばれませんでした"))
                if openFlow.hasQueued == false, NSApp.windows.allSatisfy({ !$0.isVisible }) { NSApp.terminate(nil) }
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
            reply(.success(id: request.id, .object(["location": session?.markedLocation?.json ?? .null])))
        case .getView:
            guard let session else { return reply(.success(id: request.id, .object(["view": .null]))) }
            Task { @MainActor in
                reply(.success(id: request.id, .object(["view": await session.view()])))
            }
        }
    }

    /// `hyperbuf://` の URL(起動と、外部リンクからの「開く」)。結果を返す相手はいない。
    func handle(url: URL) {
        switch OpenURL.parse(url) {
        case .success(let request) where request.op == RequestOperation.open.rawValue:
            openFlow.submit(request, reply: nil)
        case .success:
            break  // ping: アプリを起動するだけ
        case .failure(let error):
            session?.deliverOpen(["id": UUID().uuidString, "path": "", "error": error.message])
        }
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
            if let project = ProjectPicker.fromArguments() {
                model.open(project)
                if let n = ProcessInfo.processInfo.environment["HYPERBUF_SPIKE_FRAMES"].flatMap(Int.init) {
                    try? await Task.sleep(for: .seconds(1))
                    Spike.run(model: model, count: n)
                }
                return
            }
            // URL スキームで起動された場合、「開く」要求が、少し遅れて届く。要求があれば、そのファイルを手がかりに
            // プロジェクトを選んでもらい、なければ、通常どおり選んでもらう。
            try? await Task.sleep(for: .milliseconds(400))
            if model.session == nil && !model.openFlow.hasQueued {
                model.requestProjectSelection(startingAt: nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls { AppModel.shared.handle(url: url) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 画面の状態(window の配置・履歴・閲覧位置)を、保存してから終わる
        guard let session = AppModel.shared.session else { return .terminateNow }
        Task { @MainActor in
            await session.flushSession()
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
    private let model = AppModel.shared

    var body: some Scene {
        Window("HyperBuf", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("プロジェクトを開く…") { model.chooseProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let web = model.web, let session = model.session {
                WebShell(session: session, web: web, openFlow: model.openFlow)
                    .id(session.id)
                    .navigationTitle("HyperBuf — \(session.project.name)")
            } else if model.web == nil {
                Text("Web コア(core/dist)が見つかりません。`npm run build`(core/)を実行してください。")
                    .padding()
            } else {
                Color.clear
            }
        }
    }
}
