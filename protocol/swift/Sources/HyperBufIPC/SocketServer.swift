// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Darwin
import Foundation
import HyperBufProtocol

/// Unix domain socket server (docs/dev/integration-protocol.md §3).
///  - Directory 0700 / socket 0600. For each connection, checks that the peer's user ID is the same as the app's
///  - UTF-8 JSON Lines (one message per line, up to 1 MiB). One connection can process several requests concurrently
///  - At startup, if the existing socket accepts a connection it is "already running"; otherwise it is recreated as
/// stale
public final class SocketServer: @unchecked Sendable {
    public enum StartError: Error, Equatable {
        case alreadyRunning
        case pathTooLong
        case system(String)
    }

    public typealias Reply = @Sendable (Response) -> Void
    /// Handles a validated request (operation and version already checked). Not necessarily on the main thread.
    /// `reply` must be called exactly once, from any thread at any time (it may take long, e.g. waiting for
    /// confirmation).
    public typealias Handler = @Sendable (Request, RequestOperation, @escaping Reply) -> Void

    public let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.yhojo.hyperbuf.socket", attributes: .concurrent)
    private let lock = NSLock()
    private var listenFd: Int32 = -1

    public init(path: String = SocketPath.standard(), handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    // MARK: Start / stop

    private static func makeAddr(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            for (i, byte) in bytes.enumerated() { buffer[i] = byte }
            buffer[bytes.count] = 0
        }
        return addr
    }

    /// Whether the existing socket accepts a connection (= whether another instance responds).
    public static func isListening(at path: String) -> Bool {
        guard var addr = makeAddr(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }

    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        guard var addr = SocketServer.makeAddr(path) else { throw StartError.pathTooLong }
        if FileManager.default.fileExists(atPath: path) {
            if SocketServer.isListening(at: path) { throw StartError.alreadyRunning }
            unlink(path)  // no response = a stale socket left by a previous abnormal exit
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.system("socket: \(String(cString: strerror(errno)))") }
        // umask is a process-wide setting and would affect file creation on other threads, so it is not used.
        // The directory of the location is 0700, so no other user can get in between bind and chmod.
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw StartError.system("bind: \(String(cString: strerror(errno)))")
        }
        chmod(path, 0o600)
        guard listen(fd, SOMAXCONN) == 0 else {
            close(fd)
            throw StartError.system("listen: \(String(cString: strerror(errno)))")
        }
        lock.lock()
        listenFd = fd
        lock.unlock()
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    public func stop() {
        lock.lock()
        let fd = listenFd
        listenFd = -1
        lock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
            unlink(path)
        }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // closed by stop()
            }
            queue.async { [self] in serve(Connection(fd: client)) }
        }
    }

    // MARK: Connections

    /// One connection. Even if the client closes its send side, it is not closed while requests are unanswered, so
    /// responses can still be written.
    private final class Connection: @unchecked Sendable {
        let fd: Int32
        private let lock = NSLock()
        private var outstanding = 0
        private var eof = false
        private var closed = false

        init(fd: Int32) { self.fd = fd }

        func begin() {
            lock.lock()
            outstanding += 1
            lock.unlock()
        }

        func write(_ response: Response) {
            guard var data = try? JSONEncoder().encode(response) else { return finishOne() }
            data.append(10)
            lock.lock()
            if !closed {
                data.withUnsafeBytes { raw in
                    var sent = 0
                    while sent < raw.count {
                        let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                        if n <= 0 { break }
                        sent += n
                    }
                }
            }
            lock.unlock()
            finishOne()
        }

        /// Finish without writing a response (a failure where no response is possible).
        func finishOne() {
            lock.lock()
            outstanding -= 1
            let done = eof && outstanding <= 0
            lock.unlock()
            if done { close() }
        }

        func markEOF() {
            lock.lock()
            eof = true
            let done = outstanding <= 0
            lock.unlock()
            if done { close() }
        }

        func close() {
            lock.lock()
            defer { lock.unlock() }
            if !closed {
                closed = true
                Darwin.close(fd)
            }
        }
    }

    private func serve(_ conn: Connection) {
        // The peer must be a process of the same user as the app
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(conn.fd, &uid, &gid) == 0, uid == geteuid() else {
            conn.close()
            return
        }
        var framer = LineFramer()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(conn.fd, &chunk, chunk.count)
            if n <= 0 { return conn.markEOF() }
            let lines: [Data]
            do {
                lines = try framer.append(Data(chunk[0..<n]))
            } catch {
                conn.begin()
                conn.write(.failure(id: nil, ProtocolError(.badRequest, "Line too large")))
                return conn.markEOF()
            }
            for line in lines { dispatch(line, conn) }
        }
    }

    private func dispatch(_ line: Data, _ conn: Connection) {
        conn.begin()
        guard let request = try? JSONDecoder().decode(Request.self, from: line) else {
            return conn.write(.failure(id: nil, ProtocolError(.badRequest, "Cannot parse as JSON")))
        }
        if let v = request.v, v != HyperBufProtocol.version {
            return conn.write(
                .failure(id: request.id, ProtocolError(.unsupportedVersion, "Unsupported version (v=\(v))")))
        }
        guard let operation = RequestOperation(rawValue: request.op) else {
            return conn.write(
                .failure(id: request.id, ProtocolError(.unknownOp, "Unsupported operation: \(request.op)")))
        }
        let once = OnceFlag()
        handler(request, operation) { response in
            guard once.take() else { return }
            var r = response
            if r.id == nil { r.id = request.id }
            conn.write(r)
        }
    }
}

/// A marker so the response is written only once.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
