// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

@testable import HyperBufKit

/// Creates a test project in a temporary directory.
struct TempProject {
    let url: URL

    init(files: [String: String] = [:]) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hyperbuf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (path, text) in files { try write(path, text) }
    }

    func write(_ path: String, _ text: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// A path in `realpath` form (`/var/...` becomes `/private/var/...`). Use this for judging and comparing.
    var real: String { PathUtil.canonicalPath(url.path) ?? url.path }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Cleans up several test projects together.
func removeAll(_ projects: TempProject...) {
    for project in projects { project.remove() }
}
