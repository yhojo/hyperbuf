// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Darwin
import Foundation
import HyperBufProtocol

/// Unix ドメインソケットのクライアント(`hyperbuf` CLI が使う)。1 回の要求と、1 回の応答。
public enum SocketClient {
    public enum ClientError: Error, Equatable {
        /// ソケットがない、または、待ち受けていない(アプリが起動していない)。
        case notRunning
        /// 期限までに、応答が届かなかった。
        case timeout
        /// 応答を解釈できなかった、または、応答の前に接続が閉じた。
        case badResponse
        case system(String)
    }

    /// 要求を送り、応答を 1 つ受け取る。`id` のない応答(サーバーが要求を解釈できなかったとき)も、受け取る。
    public static func send(_ request: Request, to path: String, timeout: TimeInterval) throws -> Response {
        let fd = try connect(path)
        defer { close(fd) }

        var data = try JSONEncoder().encode(request)
        data.append(10)
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n <= 0 { throw ClientError.system("write: \(String(cString: strerror(errno)))") }
                sent += n
            }
        }

        var framer = LineFramer()
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw ClientError.timeout }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&p, 1, Int32(min(remaining * 1000, 1000)))
            if ready < 0, errno != EINTR { throw ClientError.system("poll: \(String(cString: strerror(errno)))") }
            if ready <= 0 { continue }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { throw ClientError.badResponse }
            let lines = (try? framer.append(Data(chunk[0..<n]))) ?? []
            if let line = lines.first {
                guard let response = try? JSONDecoder().decode(Response.self, from: line) else {
                    throw ClientError.badResponse
                }
                return response
            }
        }
    }

    /// ソケットが、待ち受けているか(アプリが起動しているか)。
    public static func isListening(at path: String) -> Bool {
        guard let fd = try? connect(path) else { return false }
        close(fd)
        return true
    }

    private static func connect(_ path: String) throws -> Int32 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw ClientError.notRunning }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            for (i, byte) in bytes.enumerated() { buffer[i] = byte }
            buffer[bytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.system("socket: \(String(cString: strerror(errno)))") }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        if !ok {
            let error = errno
            close(fd)
            // ソケットがない(ENOENT)、待ち受けていない(ECONNREFUSED)は、アプリが起動していない
            if error == ENOENT || error == ECONNREFUSED { throw ClientError.notRunning }
            throw ClientError.system("connect: \(String(cString: strerror(error)))")
        }
        return fd
    }
}
