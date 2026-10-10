// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import HyperBufKit
import SwiftUI
import WebKit

/// WKWebView を SwiftUI に載せる。Web コアは、同梱したファイルをカスタムスキームで読む。
struct WebShell: NSViewRepresentable {
    let frame: FrameSession
    let web: StaticFiles
    let model: AppModel

    func makeNSView(context: Context) -> WKWebView {
        let bridge = Bridge(frame: frame, model: model)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            SchemeHandler(web: web, access: frame.access), forURLScheme: ContentSecurityPolicy.scheme)
        config.userContentController.addScriptMessageHandler(
            bridge, contentWorld: .page, name: Bridge.handlerName)
        config.userContentController.addUserScript(
            WKUserScript(
                source: Bridge.script(home: frame.access.home), injectionTime: .atDocumentStart,
                forMainFrameOnly: true))
        let view = EditorWebView(frame: .zero, configuration: config)
        view.editMenuTitle = frame.editorConfig.menuTitle
        view.onEditRequested = { [weak frame] in frame?.requestEdit() }
        #if DEBUG
            view.isInspectable = true
        #endif
        frame.webView = view
        context.coordinator.bridge = bridge  // WKUserContentController は、ハンドラを強参照しない
        TestHarness.attach(to: view, bridge: bridge, slot: frame.slot)
        TestHarness.startCommandChannel(for: view, slot: frame.slot)
        view.load(URLRequest(url: URL(string: "\(ContentSecurityPolicy.scheme)://app/index.html")!))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var bridge: Bridge?
    }
}
