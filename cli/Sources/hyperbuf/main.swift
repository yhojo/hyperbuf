import Foundation
import HyperBufCLI
import HyperBufIPC
import HyperBufProtocol

// hyperbuf コマンド。仕様: docs/integration-protocol.md
let environment = ProcessInfo.processInfo.environment

// 開発・テスト用の差し替え: HYPERBUF_SOCKET_PATH(ソケット)、HYPERBUF_APP(.app のパス)
let env = CLI.Environment(
    cwd: FileManager.default.currentDirectoryPath,
    socketPath: environment["HYPERBUF_SOCKET_PATH"] ?? SocketPath.standard(),
    launcher: OpenCommandLauncher(appPath: environment["HYPERBUF_APP"]),
    stdout: { print($0) },
    stderr: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
)
exit(CLI.run(Array(CommandLine.arguments.dropFirst()), env))
