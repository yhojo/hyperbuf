import SwiftUI
import WebKit

// Interaction PoC のシェル(SwiftUI + WKWebView)。
// Web コア(poc/web)をカスタムスキームで配信し、ファイルアクセスはホストブリッジ経由に限る。

// hyperbuf://open?... を受け取る(docs/integration-protocol.md)。SwiftUI の onOpenURL は WindowGroup だと
// URL ごとに新しいウィンドウを作ってしまうため、AppDelegate で受け取り、ウィンドウは 1 つに保つ。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { Host.shared.handleOpenURL($0) }
    }
}

@main
struct HyperbufPoc: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        Window("hyperbuf-poc", id: "main") {
            WebContainer()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

struct WebContainer: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let host = Host.shared
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(host, forURLScheme: Host.scheme)
        config.userContentController.addScriptMessageHandler(host, contentWorld: .page, name: "host")
        config.userContentController.addUserScript(
            WKUserScript(source: Host.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.isInspectable = true
        host.webView = view
        view.load(URLRequest(url: URL(string: "\(Host.scheme)://app/index.html")!))
        host.startWatching()
        host.startSocketServer()
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
