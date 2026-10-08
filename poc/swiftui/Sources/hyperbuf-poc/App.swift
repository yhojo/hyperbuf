import SwiftUI
import WebKit

// Interaction PoC のシェル(SwiftUI + WKWebView)。
// Web コア(poc/web)をカスタムスキームで配信し、ファイルアクセスはホストブリッジ経由に限る。

@main
struct HyperbufPoc: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
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
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
