import AppKit

// SwiftUI の `App` は使わず、AppKit で起動する(メニューは MainMenu、ウィンドウは AppModel が作る)。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}
