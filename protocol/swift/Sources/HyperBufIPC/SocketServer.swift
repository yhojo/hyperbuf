import Darwin
import Foundation
import HyperBufProtocol

/// Unix ドメインソケットのサーバー(docs/integration-protocol.md §11)。
///  - ディレクトリ 0700 / ソケット 0600。接続ごとに、相手のユーザー ID が、アプリと同じかを確認する
///  - UTF-8 の JSON Lines(1 行 1 メッセージ、上限 1 MiB)。1 つの接続で複数の要求を、並行して処理できる
///  - 起動時、既存のソケットに接続できれば「すでに起動中」、できなければ古いソケットとして作り直す
public final class SocketServer: @unchecked Sendable {
    public enum StartError: Error, Equatable {
        case alreadyRunning
        case pathTooLong
        case system(String)
    }

    public typealias Reply = @Sendable (Response) -> Void
    /// 検証済みの要求(操作とバージョンは確認済み)を処理する。メインスレッドとは限らない。
    /// `reply` は、任意のスレッド・任意の時点で、1 回だけ呼ぶ(確認待ちなど、時間がかかってもよい)。
    public typealias Handler = @Sendable (Request, RequestOperation, @escaping Reply) -> Void

    public let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "dev.hyperbuf.socket", attributes: .concurrent)
    private let lock = NSLock()
    private var listenFd: Int32 = -1

    public init(path: String = SocketPath.standard(), handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    // MARK: 起動・停止

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

    /// 既存のソケットに接続できるか(= 別のインスタンスが応答するか)。
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
            unlink(path)  // 応答がない = 前回の異常終了で残った古いソケット
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.system("socket: \(String(cString: strerror(errno)))") }
        // umask は、プロセス全体の設定で、他のスレッドのファイル作成にも影響するため、使わない。
        // 置き場所のディレクトリが 0700 なので、bind から chmod までの間も、他のユーザーは入れない。
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
                return  // stop() で閉じられた
            }
            queue.async { [self] in serve(Connection(fd: client)) }
        }
    }

    // MARK: 接続

    /// 1 つの接続。クライアントが送信側を閉じても、未応答の要求があるあいだは、応答を書けるよう、閉じない。
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

        /// 応答を書かずに終える(応答できない失敗)。
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
        // 接続元は、アプリと同じユーザーのプロセスだけ
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
                conn.write(.failure(id: nil, ProtocolError(.badRequest, "1 行が大きすぎます")))
                return conn.markEOF()
            }
            for line in lines { dispatch(line, conn) }
        }
    }

    private func dispatch(_ line: Data, _ conn: Connection) {
        conn.begin()
        guard let request = try? JSONDecoder().decode(Request.self, from: line) else {
            return conn.write(.failure(id: nil, ProtocolError(.badRequest, "JSON として解釈できません")))
        }
        if let v = request.v, v != HyperBufProtocol.version {
            return conn.write(
                .failure(id: request.id, ProtocolError(.unsupportedVersion, "未対応のバージョンです(v=\(v))")))
        }
        guard let operation = RequestOperation(rawValue: request.op) else {
            return conn.write(
                .failure(id: request.id, ProtocolError(.unknownOp, "未対応の操作です: \(request.op)")))
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

/// 応答を 1 回だけ書くための印。
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
