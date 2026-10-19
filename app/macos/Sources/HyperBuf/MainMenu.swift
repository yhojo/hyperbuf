// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import HyperBufKit

/// The menu bar. SwiftUI's `App` / `Scene` are not used (frame windows are made with AppKit, so no empty settings window etc. appears).
/// Switching frames (`Cmd-1` ... `Cmd-9`) is the shortcut of Window menu items, so it works even when the WebView has focus
/// (only the items of open frames are listed; `AppModel.refreshWindowMenu`).
@MainActor
enum MainMenu {
    static func install(model: AppModel) {
        let main = NSMenu()
        main.addItem(item(appMenu(model: model)))
        main.addItem(item(fileMenu(model: model)))
        main.addItem(item(editMenu()))
        let window = windowMenu()
        main.addItem(item(window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
        model.windowMenu = window
        model.refreshWindowMenu()
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
        entry(menu, "About HyperBuf", #selector(AppModel.menuAbout(_:)), target: model)
        entry(menu, "Show Third-Party Licenses", #selector(AppModel.menuShowNotices(_:)), target: model)
        menu.addItem(.separator())
        entry(menu, "Show Config File in Finder", #selector(AppModel.menuRevealConfig(_:)), target: model)
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        entry(menu, "Hide HyperBuf", #selector(NSApplication.hide(_:)), "h")
        entry(
            menu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
            modifiers: [.command, .option])
        entry(menu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        entry(menu, "Quit HyperBuf", #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    private static func fileMenu(model: AppModel) -> NSMenu {
        let menu = NSMenu(title: "File")
        entry(menu, "New Frame", #selector(AppModel.menuNewFrame(_:)), "n", target: model)
        entry(menu, "Open File…", #selector(AppModel.menuOpenFile(_:)), "o", target: model)
        menu.addItem(.separator())
        entry(menu, "Close Frame", #selector(NSWindow.performClose(_:)), "w")
        return menu
    }

    /// Edit: copy and the like reach the focused WebView (first responder).
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        entry(menu, "Copy", #selector(NSText.copy(_:)), "c")
        entry(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        entry(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        entry(menu, "Zoom", #selector(NSWindow.performZoom(_:)))
        entry(
            menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control])
        return menu
    }
}
