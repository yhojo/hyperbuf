import Foundation

/// 同梱した Web コア(`core/dist`)の置き場所。
enum WebRoot {
    /// 優先順: 環境変数 `HYPERBUF_WEB_ROOT` → アプリのバンドル(`Contents/Resources/web`)→ (デバッグビルドのみ)`core/dist`。
    static func locate() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["HYPERBUF_WEB_ROOT"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("web"))
        }
        #if DEBUG
            // app/macos/Sources/HyperBuf/WebRoot.swift から、リポジトリの core/dist へ
            candidates.append(
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("core/dist"))
        #endif
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }
}
