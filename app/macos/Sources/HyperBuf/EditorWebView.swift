// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import WebKit

/// WKWebView に、右クリックメニューの項目「<エディタ> で編集」を足す(「翻訳」などと同じメニュー)。
/// 項目を選ぶと、Web コアが、指した場所(選択・クリック位置)を、元の Markdown の位置にして、記録する。
final class EditorWebView: WKWebView {
    var onEditRequested: (() -> Void)?
    var editMenuTitle = "エディタで編集"

    // 起動直後から、クリックなしでキー操作を受け付ける。WKWebView は、ウィンドウに載っても、
    // 自分では、ファーストレスポンダにならない(クリックして初めてなる)
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
        // ウィンドウを閉じるときも、セッションを保存する(最後のウィンドウなら、そのまま終了する)
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

    /// テキスト入力中は、奪わない。
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
