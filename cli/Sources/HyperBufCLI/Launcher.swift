// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// アプリの起動(アプリが起動していないとき)。`hyperbuf://` の URL を、`open` に渡す。
/// 起動と、最初の要求の引き渡しを、1 回で行う(アプリが、その URL の指すファイルから、プロジェクトを選んでもらう)。
public protocol AppLauncher: Sendable {
    func launch(url: URL, activate: Bool) throws
}

public struct LaunchError: Error, Equatable {
    public let message: String
    public init(message: String) { self.message = message }
}

public struct OpenCommandLauncher: AppLauncher {
    /// 開発用: `.app` のパス(`HYPERBUF_APP`)。指定がなければ、URL スキームに登録されたアプリが起動する。
    public let appPath: String?

    public init(appPath: String?) { self.appPath = appPath }

    public func launch(url: URL, activate: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // 引数は配列で渡す(シェルを介さない)。URL は、HyperBufProtocol が組み立てたもの。
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
