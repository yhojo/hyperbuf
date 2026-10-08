import AppKit
import HyperBufKit
import SwiftUI

/// いま開いているプロジェクト。切り替えると、WebView ごと作り直す。
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    var session: ProjectSession?
    let web: StaticFiles?

    private init() {
        web = WebRoot.locate().map(StaticFiles.init(root:))
    }

    func open(_ project: Project) {
        session = ProjectSession(project: project)
    }

    func chooseProject() {
        if let project = ProjectPicker.choose() { open(project) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` のように、アプリのバンドルなしで起動したときも、通常のアプリとして前面に出す
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let model = AppModel.shared
            if let project = ProjectPicker.fromArguments() {
                model.open(project)
            } else {
                model.chooseProject()
                if model.session == nil { NSApplication.shared.terminate(nil) }
            }
        }
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
                WebShell(session: session, web: web)
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
