// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufCLI

final class TempDir {
    let path: String

    init() throws {
        let base = (NSTemporaryDirectory() as NSString).standardizingPath
        path = base + "/hbcli-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func write(_ relative: String, _ text: String) throws {
        let file = path + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: file, atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(atPath: path) }
}

/// Records of stdout/stderr and of launches.
final class Output: @unchecked Sendable {
    private let lock = NSLock()
    private var outLines: [String] = []
    private var errLines: [String] = []
    private var launches: [URL] = []

    var out: [String] { lock.withLock { outLines } }
    var err: String { lock.withLock { errLines.joined(separator: "\n") } }
    var launched: [URL] { lock.withLock { launches } }

    func environment(
        cwd: String, socketPath: String, launcher: (any AppLauncher)? = nil
    ) -> CLI.Environment {
        let recorder = launcher ?? RecordingLauncher(output: self)
        return CLI.Environment(
            cwd: cwd, socketPath: socketPath, launcher: recorder,
            stdout: { [self] line in lock.withLock { outLines.append(line) } },
            stderr: { [self] line in lock.withLock { errLines.append(line) } })
    }

    fileprivate func recordLaunch(_ url: URL) { lock.withLock { launches.append(url) } }
}

/// Records the launch request instead of actually launching.
struct RecordingLauncher: AppLauncher {
    let output: Output
    func launch(url: URL, activate: Bool) throws { output.recordLaunch(url) }
}

struct FailingLauncher: AppLauncher {
    func launch(url: URL, activate: Bool) throws { throw LaunchError(message: "起動できません") }
}
