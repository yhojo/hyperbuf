// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufIPC
import HyperBufProtocol

public let cliVersion = "0.1.2"

/// `hyperbuf` コマンドの本体。入出力・環境・アプリへの依頼を注入できるようにして、テストする。
public struct CLI: Sendable {
    public struct Environment: Sendable {
        public var cwd: String
        public var socketPath: String
        public var launcher: any AppLauncher
        public var stdout: @Sendable (String) -> Void
        public var stderr: @Sendable (String) -> Void
        /// 起動直後の、ソケットの出現を待つ期限(秒)。
        public var launchWait: TimeInterval = 15
        /// アプリ内の確認を待つ期限(ミリ秒)。`--wait` のときは `waitTimeoutMs`。
        public var timeoutMs = CLI.defaultTimeoutMs
        public var waitTimeoutMs = CLI.waitTimeoutMs

        public init(
            cwd: String, socketPath: String, launcher: any AppLauncher,
            stdout: @escaping @Sendable (String) -> Void, stderr: @escaping @Sendable (String) -> Void
        ) {
            self.cwd = cwd
            self.socketPath = socketPath
            self.launcher = launcher
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public static let defaultTimeoutMs = 3_000
    public static let waitTimeoutMs = 60_000

    public static func run(_ arguments: [String], _ env: Environment) -> Int32 {
        switch Arguments.parse(arguments) {
        case .failure(let error):
            env.stderr("hyperbuf: \(error.message)\n\n\(Arguments.usage)")
            return ExitCode.usage.rawValue
        case .success(.help):
            env.stdout(Arguments.usage)
            return ExitCode.success.rawValue
        case .success(.version):
            env.stdout("hyperbuf \(cliVersion)")
            return ExitCode.success.rawValue
        case .success(.open(let options)):
            return open(options, env).rawValue
        }
    }

    private static func open(_ options: OpenOptions, _ env: Environment) -> ExitCode {
        // 先に、すべてのファイルを確かめる(途中まで開いてから、失敗することを避ける)
        var requests: [Request] = []
        for file in options.files {
            switch FileResolver.resolve(file, cwd: env.cwd) {
            case .failure(let failure):
                env.stderr("hyperbuf: \(failure.message)")
                return .file
            case .success(let resolved):
                requests.append(
                    Request(
                        id: "cli-\(getpid())-\(requests.count + 1)", op: .open, path: resolved.path,
                        line: options.line ?? resolved.line, anchor: options.anchor,
                        target: options.target,
                        timeoutMs: options.wait ? env.waitTimeoutMs : env.timeoutMs))
            }
        }

        if options.printURL {
            for request in requests {
                var plain = request
                plain.id = nil
                plain.timeoutMs = nil
                guard let url = OpenURL.make(plain) else { return .failure }
                env.stdout(url.absoluteString)
            }
            return .success
        }

        var remaining = requests[...]
        var launched = false
        while let request = remaining.first {
            do {
                let timeout = Double(request.timeoutMs ?? env.timeoutMs) / 1000 + 2
                let response = try SocketClient.send(request, to: env.socketPath, timeout: timeout)
                if let error = response.error { return report(error, env) }
                remaining = remaining.dropFirst()
            } catch SocketClient.ClientError.notRunning {
                if launched {
                    env.stderr("hyperbuf: cannot connect to the launched app")
                    return .cannotLaunch
                }
                // アプリが起動していない: `hyperbuf://ping`(起動だけ)で起動し、ソケットが現れるのを待って、
                // ソケットで送る。URL スキームは、起点を特定できない経路なので、許可パスにないファイルは確認が
                // 出る。CLI の要求は、すべてソケットを通す(docs/dev/file-access.md §2)
                guard let url = OpenURL.make(Request(op: .ping)) else { return .failure }
                do {
                    try env.launcher.launch(url: url, activate: !options.noActivate)
                } catch let error as LaunchError {
                    env.stderr("hyperbuf: \(error.message)")
                    return .cannotLaunch
                } catch {
                    env.stderr("hyperbuf: cannot launch the app: \(error)")
                    return .cannotLaunch
                }
                launched = true
                if !waitForSocket(env) {
                    env.stderr("hyperbuf: cannot connect to the launched app")
                    return .cannotLaunch
                }
                // 同じ要求を、ソケットで送り直す(`remaining` は、そのまま)
            } catch SocketClient.ClientError.timeout {
                env.stderr(
                    "hyperbuf: no response from the app (it may be waiting for confirmation; use --wait to wait longer)"
                )
                return .refused
            } catch {
                env.stderr("hyperbuf: communication with the app failed: \(error)")
                return .failure
            }
        }
        return .success
    }

    private static func waitForSocket(_ env: Environment) -> Bool {
        let deadline = Date().addingTimeInterval(env.launchWait)
        while Date() < deadline {
            if SocketClient.isListening(at: env.socketPath) {
                // 起動直後は、Web コアの準備が終わるまで、少し待つほうがよい(要求はアプリ側で保留される)
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// アプリが返したエラーを、終了コードにする。
    static func report(_ error: ProtocolError, _ env: Environment) -> ExitCode {
        env.stderr("hyperbuf: \(error.message)")
        switch ErrorCode(rawValue: error.code) {
        case .notFound, .notMarkdown: return .file
        case .badRequest: return .usage
        case .outsideProject, .timeout, .stale: return .refused
        case .unsupportedVersion, .unknownOp, .internal, .none: return .failure
        }
    }
}
