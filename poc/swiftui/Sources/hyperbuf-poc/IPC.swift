import AppKit
import Darwin
import Foundation

// IPC(Unix ドメインソケット)のサーバー。docs/integration-protocol.md §11。
//  - ディレクトリ 0700 / ソケット 0600、接続ごとに相手のユーザー ID を確認する
//  - UTF-8 の JSON Lines(1 行 1 メッセージ、上限 1 MiB)
//  - 起動時、既存のソケットに接続できれば「すでに起動中」、できなければ古いソケットとして作り直す

final class SocketServer {
    enum StartError: Error { case alreadyRunning, pathTooLong, system(String) }

    static func defaultPath() -> String {
        NSString(string: "~/Library/Application Support/Hyperbuf/hyperbuf.sock").expandingTildeInPath
    }

    /// 要求の処理(メインスレッドで呼ばれる)。reply は任意のスレッド・任意の時点で呼べる。
    var handler: ((_ request: [String: Any], _ reply: @escaping ([String: Any]) -> Void) -> Void)?

    let path: String
    private var listenFd: Int32 = -1
    private let queue = DispatchQueue(label: "hyperbuf.socket", attributes: .concurrent)
    private static let maxLine = 1 << 20

    init(path: String = SocketServer.defaultPath()) { self.path = path }

    private static func makeAddr(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        return addr
    }

    private static func canConnect(_ path: String) -> Bool {
        guard var addr = makeAddr(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        guard var addr = SocketServer.makeAddr(path) else { throw StartError.pathTooLong }
        if FileManager.default.fileExists(atPath: path) {
            if SocketServer.canConnect(path) { throw StartError.alreadyRunning }
            unlink(path)  // 応答がない = 前回の異常終了で残った古いソケット
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.system("socket: \(String(cString: strerror(errno)))") }
        let oldMask = umask(0o177)  // bind の時点から 0600 にする
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(oldMask)
        guard bound == 0 else { close(fd); throw StartError.system("bind: \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { close(fd); throw StartError.system("listen: \(String(cString: strerror(errno)))") }
        listenFd = fd
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
        unlink(path)
    }

    private func acceptLoop() {
        while listenFd >= 0 {
            let client = accept(listenFd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        // 接続元は、アプリと同じユーザーのプロセスだけ
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { return }

        let writeLock = NSLock()
        let write: ([String: Any]) -> Void = { obj in
            guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
            data.append(10)
            writeLock.lock()
            defer { writeLock.unlock() }
            data.withUnsafeBytes { raw in
                var sent = 0
                while sent < raw.count {
                    let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                    if n <= 0 { return }
                    sent += n
                }
            }
        }
        let fail: (Any?, String, String) -> Void = { id, code, message in
            var r: [String: Any] = ["v": 1, "ok": false, "error": ["code": code, "message": message]]
            if let id { r["id"] = id }
            write(r)
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(chunk, count: n)
            while let nl = buffer.firstIndex(of: 10) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    fail(nil, "bad-request", "JSON として解釈できません")
                    continue
                }
                let id = obj["id"]
                DispatchQueue.main.async { [weak self] in
                    guard let handler = self?.handler else { return fail(id, "bad-request", "未初期化です") }
                    handler(obj) { result in
                        var r = result
                        r["v"] = 1
                        if let id { r["id"] = id }
                        write(r)
                    }
                }
            }
            if buffer.count > SocketServer.maxLine {
                fail(nil, "bad-request", "1 行が大きすぎます")
                return
            }
        }
    }
}

// MARK: 要求の処理

extension Host {
    func startSocketServer() {
        let server = SocketServer()
        server.handler = { [weak self] request, reply in self?.handleIPC(request, reply) }
        do {
            try server.start()
            socketServer = server
            log("SOCKET_LISTEN \(server.path)")
        } catch {
            log("SOCKET_ERROR \(error)")
        }
    }

    private func errorReply(_ code: String, _ message: String) -> [String: Any] {
        ["ok": false, "error": ["code": code, "message": message]]
    }

    fileprivate func handleIPC(_ request: [String: Any], _ reply: @escaping ([String: Any]) -> Void) {
        if let v = request["v"], "\(v)" != "1" { return reply(errorReply("unsupported-version", "未対応のバージョンです(v=\(v))")) }
        switch request["op"] as? String {
        case "ping":
            reply(["ok": true, "result": ["version": "0.0.0-poc", "pid": ProcessInfo.processInfo.processIdentifier, "protocol": 1]])
        case "open":
            switch validateOpen(
                path: request["path"] as? String, line: request["line"], anchor: request["anchor"] as? String, version: nil)
            {
            case .failure(let e):
                reply(errorReply(e.code, e.message))
            case .success(var req):
                // ページの処理(範囲外ならミニバッファでの確認を含む)が終わるまで、応答を保留する
                let id = UUID().uuidString
                req["id"] = id
                pendingReplies[id] = reply
                let timeout = (request["timeoutMs"] as? Int) ?? 30_000
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeout)) { [weak self] in
                    if let r = self?.pendingReplies.removeValue(forKey: id) {
                        r(["ok": false, "error": ["code": "timeout", "message": "ユーザーの回答がありませんでした"]])
                    }
                }
                NSApp.activate(ignoringOtherApps: true)
                if pageReady { deliver(req) } else { pendingOpens.append(req) }
            }
        case "get-location":
            let js = "return window.__hostQuery ? await window.__hostQuery('get-location') : null"
            webView?.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): reply(["ok": true, "result": ["location": value ?? NSNull()]])
                case .failure(let error): reply(["ok": false, "error": ["code": "internal", "message": "\(error)"]])
                }
            }
        default:
            reply(errorReply("unknown-op", "未対応の操作です: \(request["op"] ?? "nil")"))
        }
    }
}
