// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufCLI
import HyperBufIPC
import HyperBufProtocol

// The hyperbuf command. Spec: docs/dev/integration-protocol.md
let environment = ProcessInfo.processInfo.environment

// Overrides for development/testing: HYPERBUF_SOCKET_PATH (socket), HYPERBUF_APP (path to the .app)
let env = CLI.Environment(
    cwd: FileManager.default.currentDirectoryPath,
    socketPath: environment["HYPERBUF_SOCKET_PATH"] ?? SocketPath.standard(),
    launcher: OpenCommandLauncher(appPath: environment["HYPERBUF_APP"]),
    stdout: { print($0) },
    stderr: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
)
exit(CLI.run(Array(CommandLine.arguments.dropFirst()), env))
