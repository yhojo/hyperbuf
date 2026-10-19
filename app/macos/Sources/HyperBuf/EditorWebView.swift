// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import WebKit

/// Adds the context menu item "Edit in <editor>" to the WKWebView (the same menu as "Translate" etc.).
/// When chosen, the Web core turns the location pointed at (selection / click position) into a position in the source Markdown and records it.
final class EditorWebView: WKWebView {
    var onEditRequested: (() -> Void)?
    var editMenuTitle = "Edit in Editor"

    // Accept key input right after launch without a click. A WKWebView does not become the first responder
    // by itself even when placed in a window (only after being clicked)
    private var keyObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObserver.map(NotificationCenter.default.removeObserver)
        closeObserver.map(NotificationCenter.default.removeObserver)
        keyObserver = nil
        closeObserver = nil
        guard let window else { return }
        takeKeyboardFocus()
        // Also save the session when a window is closed (for the last window, quit as is)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateJavaScript(
                    "window.__hyperbuf && window.__hyperbuf.flushSession && window.__hyperbuf.flushSession()")
            }
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.takeKeyboardFocus() }
        }
    }

    /// Does not take it away during text input.
    private func takeKeyboardFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if !(window.firstResponder is NSText) { window.makeFirstResponder(self) }
        }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let item = NSMenuItem(title: editMenuTitle, action: #selector(editInEditor(_:)), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    @objc private func editInEditor(_ sender: Any?) {
        onEditRequested?()
    }
}
