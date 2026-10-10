// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufIPC
import HyperBufProtocol
import Testing

@testable import HyperBufCLI

private func socketPath() -> String { NSTemporaryDirectory() + "hbr-\(UUID().uuidString.prefix(8))/s.sock" }

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
}

/// 受け取った要求を記録するサーバー。
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Request] = []
    var requests: [Request] { lock.withLock { items } }
    func add(_ r: Request) { lock.withLock { items.append(r) } }
}

/// 起動の要求を受けたら、ソケットのサーバーを立てる(アプリの起動の模擬)。
private final class ServerStartingLauncher: AppLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private let start: @Sendable () throws -> SocketServer
    private var launched: [URL] = []
    private var running: SocketServer?
    var urls: [URL] { lock.withLock { launched } }

    init(start: @escaping @Sendable () throws -> SocketServer) { self.start = start }

    func launch(url: URL, activate: Bool) throws {
        lock.withLock { launched.append(url) }
        let server = try start()
        lock.withLock { running = server }
    }

    func stop() { lock.withLock { running?.stop() } }
}

@Suite(.serialized) struct RunTests {
    private func server(
        _ path: String, recorder: Recorder, respond: @escaping @Sendable (Request) -> Response?
    ) throws -> SocketServer {
        let s = SocketServer(path: path) { request, _, reply in
            recorder.add(request)
            if let response = respond(request) { reply(response) }
        }
        try s.start()
        return s
    }

    @Test func sendsTheRequestAndExitsZero() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        try t.write("docs/a.md", "x")
        let recorder = Recorder()
        let s = try server(sock, recorder: recorder) { .success(id: $0.id, .object(["path": .string("docs/a.md")])) }
        defer { s.stop() }
        let output = Output()
        let code = CLI.run(["docs/a.md:12"], output.environment(cwd: t.path, socketPath: sock))
        #expect(code == 0)
        #expect(output.launched.isEmpty)
        let request = try #require(recorder.requests.first)
        #expect(request.op == "open" && request.path == t.path + "/docs/a.md" && request.line == 12)
        #expect(request.timeoutMs == CLI.defaultTimeoutMs)
    }

    @Test func waitExtendsTheTimeout() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        try t.write("a.md", "x")
        let recorder = Recorder()
        let s = try server(sock, recorder: recorder) { .success(id: $0.id) }
        defer { s.stop() }
        _ = CLI.run(["--wait", "a.md"], Output().environment(cwd: t.path, socketPath: sock))
        #expect(recorder.requests.first?.timeoutMs == CLI.waitTimeoutMs)
    }

    @Test func sendsMultipleFilesInOrderAndStopsAtTheFirstFailure() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        for name in ["a.md", "b.md", "c.md"] { try t.write(name, "x") }
        let recorder = Recorder()
        let s = try server(sock, recorder: recorder) { request in
            request.path?.hasSuffix("b.md") == true
                ? .failure(id: request.id, ProtocolError(.outsideProject, "範囲外")) : .success(id: request.id)
        }
        defer { s.stop() }
        let output = Output()
        #expect(CLI.run(["a.md", "b.md", "c.md"], output.environment(cwd: t.path, socketPath: sock)) == 4)
        #expect(
            recorder.requests.compactMap { $0.path?.split(separator: "/").last.map(String.init) } == ["a.md", "b.md"])
        #expect(output.err.contains("範囲外"))
    }

    @Test func mapsErrorCodesToExitCodes() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        try t.write("a.md", "x")
        let expected: [(ErrorCode, Int32)] = [
            (.notFound, 2), (.notMarkdown, 2), (.badRequest, 1), (.outsideProject, 4), (.timeout, 4),
            (.stale, 4), (.unsupportedVersion, 5), (.unknownOp, 5), (.internal, 5),
        ]
        for (code, exit) in expected {
            let recorder = Recorder()
            let s = try server(sock, recorder: recorder) { .failure(id: $0.id, ProtocolError(code, "m")) }
            #expect(CLI.run(["a.md"], Output().environment(cwd: t.path, socketPath: sock)) == exit, "\(code)")
            s.stop()
        }
    }

    @Test func timesOutWhenTheAppKeepsWaiting() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        try t.write("a.md", "x")
        let s = try server(sock, recorder: Recorder()) { _ in nil }  // 応答しない
        defer { s.stop() }
        let output = Output()
        var env = output.environment(cwd: t.path, socketPath: sock)
        env.timeoutMs = 100
        let started = Date()
        #expect(CLI.run(["a.md"], env) == 4)
        #expect(Date().timeIntervalSince(started) < 6)
        #expect(output.err.contains("--wait"))
    }

    @Test func launchesWithPingThenSendsTheRequestOverTheSocket() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        try t.write("docs/日本語.md", "x")
        let recorder = Recorder()
        // アプリの起動を模す: 起動の要求(URL)を受けたら、ソケットのサーバーを立てる
        let launcher = ServerStartingLauncher { [self] in try server(sock, recorder: recorder) { .success(id: $0.id) } }
        let output = Output()
        let code = CLI.run(["docs/日本語.md:5"], output.environment(cwd: t.path, socketPath: sock, launcher: launcher))
        launcher.stop()
        #expect(code == 0)
        // 起動の URL は ping(ファイルを渡さない)。要求は、ソケットで届く
        let url = try #require(launcher.urls.first)
        #expect(url.host == "ping" && !url.absoluteString.contains("path="))
        let request = try #require(recorder.requests.first)
        #expect(request.op == "open" && request.path == t.path + "/docs/日本語.md" && request.line == 5)
    }

    @Test func reportsWhenTheLaunchedAppNeverListens() throws {
        let t = try TempDir()
        defer { t.remove() }
        try t.write("a.md", "x")
        let output = Output()
        var env = output.environment(cwd: t.path, socketPath: t.path + "/no.sock")
        env.launchWait = 0.2
        #expect(CLI.run(["a.md"], env) == 3)
        let url = try #require(output.launched.first)
        #expect(url.host == "ping")
        #expect(output.err.contains("接続できません"))
    }

    @Test func reportsWhenTheAppCannotBeLaunched() throws {
        let t = try TempDir()
        defer { t.remove() }
        try t.write("a.md", "x")
        let output = Output()
        let env = output.environment(cwd: t.path, socketPath: t.path + "/no.sock", launcher: FailingLauncher())
        #expect(CLI.run(["a.md"], env) == 3)
        #expect(output.err.contains("起動できません"))
    }

    @Test func checksEveryFileBeforeSendingAnything() throws {
        let t = try TempDir()
        let sock = socketPath()
        defer {
            t.remove()
            cleanup(sock)
        }
        try t.write("a.md", "x")
        let recorder = Recorder()
        let s = try server(sock, recorder: recorder) { .success(id: $0.id) }
        defer { s.stop() }
        #expect(CLI.run(["a.md", "missing.md"], Output().environment(cwd: t.path, socketPath: sock)) == 2)
        #expect(recorder.requests.isEmpty)  // 途中まで開いてから失敗しない
    }

    @Test func versionAndHelpNeedNoApp() {
        let output = Output()
        #expect(CLI.run(["--version"], output.environment(cwd: "/", socketPath: "/nonexistent")) == 0)
        #expect(output.out == ["hyperbuf \(cliVersion)"])
        let help = Output()
        #expect(CLI.run(["--help"], help.environment(cwd: "/", socketPath: "/nonexistent")) == 0)
        #expect(help.out.first?.contains("使い方") == true)
    }
}
