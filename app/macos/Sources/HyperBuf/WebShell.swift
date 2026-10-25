// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import HyperBufKit
import SwiftUI
import WebKit

/// Hosts a WKWebView in SwiftUI. The Web core is loaded from the bundled files through a custom scheme.
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
        // The Web core keeps carrier entries in WebKit's history so this gesture can drive the reference history (setting `gestureNavigation`)
        view.allowsBackForwardNavigationGestures = UserSettings.load().gestureNavigation
        view.editMenuTitle = frame.editorConfig.menuTitle
        view.onEditRequested = { [weak frame] in frame?.requestEdit() }
        #if DEBUG
            view.isInspectable = true
        #endif
        frame.webView = view
        context.coordinator.bridge = bridge  // WKUserContentController does not hold the handler strongly
        TestHarness.attach(to: view, bridge: bridge, slot: frame.slot)
        TestHarness.startCommandChannel(for: view, slot: frame.slot) { [weak frame] in frame?.isPageReady ?? false }
        view.load(URLRequest(url: URL(string: "\(ContentSecurityPolicy.scheme)://app/index.html")!))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var bridge: Bridge?
    }
}
