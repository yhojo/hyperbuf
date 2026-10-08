import Foundation
import HyperBufKit
import WebKit

/// 1 つのプロジェクトを開いている間の状態。ファイル監視と、Web コアへの変更の通知を持つ。
@MainActor
final class ProjectSession: Identifiable {
    let id = UUID()
    let project: Project
    weak var webView: WKWebView?
    private var watcher: FSWatcher?

    init(project: Project) {
        self.project = project
        watcher = FSWatcher(root: project.root) { [weak self] paths in
            // FSWatcher は、メインキューで通知する
            MainActor.assumeIsolated {
                for path in paths { self?.notifyChanged(path) }
            }
        }
    }

    /// Web コアの `onFileChanged` に通知する。パスは JSON 文字列として渡す(注入を避ける)。
    private func notifyChanged(_ path: String) {
        guard let data = try? JSONEncoder().encode(path), let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__hostChanged && window.__hostChanged(\(json))")
    }
}
