// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Launching the app (when it is not running). Passes a `hyperbuf://` URL to `open`.
/// Launch and hand-off of the first request happen in one step (the app picks the project from the file the URL points
/// to).
public protocol AppLauncher: Sendable {
    func launch(url: URL, activate: Bool) throws
}

public struct LaunchError: Error, Equatable {
    public let message: String
    public init(message: String) { self.message = message }
}

public struct OpenCommandLauncher: AppLauncher {
    /// For development: path to the `.app` (`HYPERBUF_APP`). If unset, the app registered for the URL scheme is
    /// launched.
    public let appPath: String?

    public init(appPath: String?) { self.appPath = appPath }

    public func launch(url: URL, activate: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Arguments are passed as an array (no shell involved). The URL is the one built by HyperBufProtocol.
        var arguments: [String] = []
        if !activate { arguments.append("-g") }
        if let appPath, !appPath.isEmpty { arguments += ["-a", appPath] }
        arguments.append(url.absoluteString)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw LaunchError(message: "Cannot run open: \(error)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw LaunchError(
                message: "Cannot launch the app: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
