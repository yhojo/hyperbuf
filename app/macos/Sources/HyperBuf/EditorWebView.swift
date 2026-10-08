import AppKit
import WebKit

/// WKWebView に、右クリックメニューの項目「<エディタ> で編集」を足す(「翻訳」などと同じメニュー)。
/// 項目を選ぶと、Web コアが、指した場所(選択・クリック位置)を、元の Markdown の位置にして、記録する。
final class EditorWebView: WKWebView {
    var onEditRequested: (() -> Void)?
    var editMenuTitle = "エディタで編集"

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
