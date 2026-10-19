// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Where the bundled Web core (`core/dist`) lives.
enum WebRoot {
    /// Priority: the env var `HYPERBUF_WEB_ROOT` -> the app bundle (`Contents/Resources/web`) -> (debug builds only) `core/dist`.
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
            // From app/macos/Sources/HyperBuf/WebRoot.swift to the repository's core/dist
            candidates.append(
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("core/dist"))
        #endif
        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }
}
