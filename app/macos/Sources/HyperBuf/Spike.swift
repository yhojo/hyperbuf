import AppKit
import HyperBufKit
import SwiftUI

/// 試作(poc/frames-memory): N 個のフレーム(NSWindow + WKWebView + Web コア)を開き、それぞれで実際に文書を描画する。
/// メモリの実測用。`HYPERBUF_SPIKE_FRAMES=N` のときだけ動く。main にはマージしない。
@MainActor
enum Spike {
    private static var windows: [NSWindow] = []
    private static var sessions: [ProjectSession] = []

    static let docs = [
        "migration-plan.md", "integration-protocol.md", "project-model.md", "interaction-model.md", "session-restore.md",
    ]

    static func run(model: AppModel, count: Int) {
        guard let first = model.session, let web = model.web else { return }
        sessions = [first]
        for index in 1..<max(count, 1) {
            let session = ProjectSession(project: first.project, trusted: model.trusted)
            let hosting = NSHostingView(rootView: WebShell(session: session, web: web, openFlow: model.openFlow))
            let window = NSWindow(
                contentRect: NSRect(x: 80 + index * 40, y: 80 + index * 30, width: 900, height: 600),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = hosting
            window.title = "frame \(index + 1)"
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            sessions.append(session)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            for (index, session) in sessions.enumerated() {
                // フレームごとに、違う文書の並びを開く(実際の使い方に近づける)
                let names = (0..<3).map { docs[(index + $0) % docs.count] }
                for name in names {
                    _ = try? await session.webView?.callAsyncJavaScript(
                        "await window.__hyperbuf.open(name); await new Promise((r) => setTimeout(r, 400)); return true;",
                        arguments: ["name": name], contentWorld: .page)
                }
            }
        }
    }
}
