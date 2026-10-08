import HyperBufKit
import SwiftUI
import WebKit

/// WKWebView を SwiftUI に載せる。Web コアは、同梱したファイルをカスタムスキームで読む。
struct WebShell: NSViewRepresentable {
    let session: ProjectSession
    let web: StaticFiles
    let openFlow: OpenFlow

    func makeNSView(context: Context) -> WKWebView {
        let bridge = Bridge(session: session, openFlow: openFlow)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            SchemeHandler(web: web, access: session.fileAccess), forURLScheme: ContentSecurityPolicy.scheme)
        config.userContentController.addScriptMessageHandler(
            bridge, contentWorld: .page, name: Bridge.handlerName)
        config.userContentController.addUserScript(
            WKUserScript(source: Bridge.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
            view.isInspectable = true
        #endif
        session.webView = view
        context.coordinator.bridge = bridge  // WKUserContentController は、ハンドラを強参照しない
        TestHarness.attach(to: view, bridge: bridge)
        view.load(URLRequest(url: URL(string: "\(ContentSecurityPolicy.scheme)://app/index.html")!))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var bridge: Bridge?
    }
}
