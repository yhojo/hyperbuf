// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Darwin
import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufIPC

/// テスト用の素朴なクライアント。
private final class TestClient {
    let fd: Int32

    init?(path: String) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            for (i, b) in bytes.enumerated() { buffer[i] = b }
            buffer[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        if !ok {
            close(fd)
            return nil
        }
    }

    deinit { close(fd) }

    func send(_ text: String) {
        let data = Array(text.utf8)
        var sent = 0
        while sent < data.count {
            let n = write(fd, Array(data[sent...]), data.count - sent)
            if n <= 0 { return }
            sent += n
        }
    }

    func halfClose() { shutdown(fd, SHUT_WR) }

    private var pending = Data()

    /// 1 行読む。`timeout` 秒で来なければ nil。1 回の読み取りで複数行が届いても、残りは次の呼び出しに残す。
    func readLine(timeout: TimeInterval = 5) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let nl = pending.firstIndex(of: 10) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                return (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
            }
            guard Date() < deadline else { return nil }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&p, 1, 100) > 0 {
                var buf = [UInt8](repeating: 0, count: 65536)
                let n = read(fd, &buf, buf.count)
                if n <= 0 { return nil }
                pending.append(buf, count: n)
            }
        }
    }
}

private func shortSocketPath() -> String {
    NSTemporaryDirectory() + "hbt-\(UUID().uuidString.prefix(8))/s.sock"
}

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
}

@Suite(.serialized) struct SocketServerTests {
    /// ping には成功、open には、パスをそのまま返す(ハンドラの呼び出しを確かめる)。
    private func echoServer(_ path: String, delayMs: Int = 0) -> SocketServer {
        SocketServer(path: path) { request, operation, reply in
            let work = {
                switch operation {
                case .ping: reply(.success(id: request.id, .object(["pid": .number(1)])))
                case .open: reply(.success(id: request.id, .object(["path": .string(request.path ?? "")])))
                case .getLocation, .getView: reply(.success(id: request.id, .null))
                }
            }
            if delayMs > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: work)
            } else {
                work()
            }
        }
    }

    @Test func pingAndOpenRoundTrip() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        c.send(#"{"v":1,"id":"a","op":"ping"}"# + "\n")
        let ping = try #require(c.readLine())
        #expect(ping["ok"] as? Bool == true)
        #expect(ping["id"] as? String == "a")
        c.send(#"{"v":1,"id":"b","op":"open","path":"/x/日本語.md"}"# + "\n")
        let open = try #require(c.readLine())
        #expect((open["result"] as? [String: Any])?["path"] as? String == "/x/日本語.md")
    }

    @Test func directoryAndSocketArePrivate() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        defer { server.stop() }
        func mode(_ p: String) -> Int {
            ((try? FileManager.default.attributesOfItem(atPath: p)[.posixPermissions]) as? Int) ?? -1
        }
        #expect(mode(path) == 0o600)
        #expect(mode((path as NSString).deletingLastPathComponent) == 0o700)
    }

    @Test func rejectsBadRequestsWithoutCallingTheHandler() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let called = Counter()
        let server = SocketServer(path: path) { request, _, reply in
            called.increment()
            reply(.success(id: request.id))
        }
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        func code(_ line: String) -> String? {
            c.send(line + "\n")
            return ((c.readLine()?["error"]) as? [String: Any])?["code"] as? String
        }
        #expect(code("{broken") == "bad-request")
        #expect(code(#"{"v":1,"id":"1"}"#) == "bad-request")  // op がない
        #expect(code(#"{"v":1,"id":"2","op":"delete","path":"/tmp/x.md"}"#) == "unknown-op")
        #expect(code(#"{"v":2,"id":"3","op":"ping"}"#) == "unsupported-version")
        #expect(called.value == 0)
        // 不正な要求のあとでも、接続は使い続けられる
        c.send(#"{"v":1,"id":"4","op":"ping"}"# + "\n")
        #expect(c.readLine()?["ok"] as? Bool == true)
        #expect(called.value == 1)
    }

    @Test func numericIdsAreAnsweredAsStrings() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        c.send(#"{"id":7,"op":"ping"}"# + "\n")
        #expect(c.readLine()?["id"] as? String == "7")
    }

    @Test func pipelinedRequestsAreAllAnswered() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        c.send((1...5).map { #"{"v":1,"id":"\#($0)","op":"ping"}"# }.joined(separator: "\n") + "\n")
        var ids = Set<String>()
        for _ in 1...5 { ids.insert(c.readLine()?["id"] as? String ?? "") }
        #expect(ids == ["1", "2", "3", "4", "5"])
    }

    @Test func deferredRepliesStillArriveAfterTheClientHalfCloses() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path, delayMs: 300)  // 確認待ち(ミニバッファ)のように、時間がかかる
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        c.send(#"{"v":1,"id":"slow","op":"ping"}"# + "\n")
        c.halfClose()  // 送信側を閉じても、応答は受け取れる
        #expect(c.readLine()?["id"] as? String == "slow")
    }

    @Test func handlesManyConcurrentClients() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        defer { server.stop() }
        let ok = Counter()
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            guard let c = TestClient(path: path) else { return }
            c.send(#"{"v":1,"id":"\#(i)","op":"ping"}"# + "\n")
            if c.readLine()?["id"] as? String == "\(i)" { ok.increment() }
        }
        #expect(ok.value == 50)
    }

    @Test func onlyTheFirstReplyIsSent() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = SocketServer(path: path) { request, _, reply in
            reply(.success(id: request.id, .string("first")))
            reply(.success(id: request.id, .string("second")))
        }
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        c.send(#"{"v":1,"id":"1","op":"ping"}"# + "\n")
        #expect(c.readLine()?["result"] as? String == "first")
        #expect(c.readLine(timeout: 0.5) == nil)
    }

    @Test func tooLongLineGetsAnErrorAndTheConnectionCloses() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        defer { server.stop() }
        let c = try #require(TestClient(path: path))
        c.send(String(repeating: "a", count: HyperBufProtocol.maxLineBytes + 10))
        let r = c.readLine()
        #expect(((r?["error"]) as? [String: Any])?["code"] as? String == "bad-request")
    }

    @Test func recoversFromAStaleSocketAndDetectsALiveOne() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        // 古いソケット: bind だけして、listen せずに閉じる(異常終了で残ったファイルを模す)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            for (i, b) in path.utf8.enumerated() { buffer[i] = b }
        }
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(stale)
        #expect(FileManager.default.fileExists(atPath: path))

        let first = echoServer(path)
        try first.start()  // 古いソケットを作り直す
        defer { first.stop() }
        #expect(TestClient(path: path) != nil)

        let second = echoServer(path)
        #expect(throws: SocketServer.StartError.alreadyRunning) { try second.start() }
        // 起動中のサーバーのソケットを、壊していない
        #expect(TestClient(path: path) != nil)
    }

    @Test func stopRemovesTheSocketFile() throws {
        let path = shortSocketPath()
        defer { cleanup(path) }
        let server = echoServer(path)
        try server.start()
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func rejectsPathsThatAreTooLong() {
        let path = NSTemporaryDirectory() + String(repeating: "x", count: 120) + "/s.sock"
        let server = echoServer(path)
        #expect(throws: SocketServer.StartError.pathTooLong) { try server.start() }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() {
        lock.lock()
        n += 1
        lock.unlock()
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return n
    }
}
