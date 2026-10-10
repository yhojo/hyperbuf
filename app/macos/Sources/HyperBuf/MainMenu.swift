import AppKit
import HyperBufKit

/// メニューバー。SwiftUI の `App` / `Scene` は使わない(フレームのウィンドウは AppKit で作り、空の設定ウィンドウなどを出さない)。
/// フレームの切り替え(`Cmd-1` … `Cmd-9`)は、メニューのショートカットなので、WebView にフォーカスがあっても効く。
@MainActor
enum MainMenu {
    static func install(model: AppModel) {
        let main = NSMenu()
        main.addItem(item(appMenu(model: model)))
        main.addItem(item(fileMenu(model: model)))
        main.addItem(item(editMenu()))
        main.addItem(item(frameMenu(model: model)))
        let window = windowMenu()
        main.addItem(item(window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func item(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }

    private static func entry(
        _ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
    }

    private static func appMenu(model: AppModel) -> NSMenu {
        let menu = NSMenu(title: "HyperBuf")
        entry(menu, "HyperBuf について", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        menu.addItem(.separator())
        entry(menu, "設定ファイルの場所を表示", #selector(AppModel.menuRevealConfig(_:)), target: model)
        menu.addItem(.separator())
        let services = NSMenu(title: "サービス")
        menu.addItem(withTitle: "サービス", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        entry(menu, "HyperBuf を隠す", #selector(NSApplication.hide(_:)), "h")
        entry(menu, "ほかを隠す", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option])
        entry(menu, "すべてを表示", #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        entry(menu, "HyperBuf を終了", #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    private static func fileMenu(model: AppModel) -> NSMenu {
        let menu = NSMenu(title: "ファイル")
        entry(menu, "新しいフレーム", #selector(AppModel.menuNewFrame(_:)), "n", target: model)
        entry(menu, "ファイルを開く…", #selector(AppModel.menuOpenFile(_:)), "o", target: model)
        menu.addItem(.separator())
        entry(menu, "フレームを閉じる", #selector(NSWindow.performClose(_:)), "w")
        return menu
    }

    /// 編集: コピーなどは、フォーカスのある WebView に届く(ファーストレスポンダ)。
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "編集")
        entry(menu, "コピー", #selector(NSText.copy(_:)), "c")
        entry(menu, "すべてを選択", #selector(NSText.selectAll(_:)), "a")
        return menu
    }

    private static func frameMenu(model: AppModel) -> NSMenu {
        let menu = NSMenu(title: "フレーム")
        for slot in 1...SessionStore.maxFrames {
            entry(menu, "フレーム \(slot)", #selector(AppModel.menuActivateFrame(_:)), "\(slot)", target: model)
            menu.items.last?.tag = slot
        }
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "ウインドウ")
        entry(menu, "しまう", #selector(NSWindow.performMiniaturize(_:)), "m")
        entry(menu, "拡大/縮小", #selector(NSWindow.performZoom(_:)))
        entry(menu, "フルスクリーン", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control])
        return menu
    }
}
