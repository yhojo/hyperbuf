import Foundation
import WebKit

// ホストブリッジ: Web 側の window.hyperbufHost の実体。
//  - hyperbuf://app/* で web ディレクトリの静的ファイルを配信(file:// だと ES modules が読めない)
//  - list / read でプロジェクト配下の Markdown だけを返す(ルート外へのアクセスは拒否)
//  - 外部更新は 0.5 秒ごとの更新日時の比較で検知(PoC 用の簡易実装。本番は FSEvents 等を検討)

final class Host: NSObject, WKURLSchemeHandler, WKScriptMessageHandlerWithReply {
    static let shared = Host()
    static let scheme = "hyperbuf"

    // 既定のパスはこのソースファイルの位置から求める。引数 <web-dir> <project-dir> で上書きできる。
    private static let pocDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let webRoot: URL
    let projectRoot: URL

    weak var webView: WKWebView?
    private var timer: Timer?
    private var watcher: FSWatcher?
    private var stamps: [String: Date] = [:]

    override init() {
        let args = CommandLine.arguments
        let base = Host.pocDir
        webRoot = (args.count > 1 ? URL(fileURLWithPath: args[1]) : base.appendingPathComponent("poc/web")).standardizedFileURL
        projectRoot = (args.count > 2 ? URL(fileURLWithPath: args[2]) : base.appendingPathComponent("poc/sample")).standardizedFileURL
        super.init()
    }

    static let bridgeScript = """
    (() => {
      const cbs = [];
      const call = (msg) => window.webkit.messageHandlers.host.postMessage(msg);
      window.hyperbufHost = {
        name: "swiftui+wkwebview",
        listFiles: () => call({ op: "list" }),
        readFile: (path) => call({ op: "read", path }),
        onFileChanged: (cb) => cbs.push(cb),
        search: (query, opts = {}) => call({ op: "search", query, ...opts }),
        resolveResource: (path) => "hyperbuf://project/" + path.split("/").map(encodeURIComponent).join("/"),
      };
      window.__hostChanged = (path) => cbs.forEach((cb) => cb(path));
      // 診断用: CSP 違反とエラーを起動時から記録する
      window.__diag = { violations: [], errors: [] };
      document.addEventListener("securitypolicyviolation", (e) => window.__diag.violations.push(e.violatedDirective + " " + e.blockedURI));
      window.addEventListener("error", (e) => window.__diag.errors.push(String(e.message)));
      window.addEventListener("unhandledrejection", (e) => window.__diag.errors.push("rejection: " + String(e.reason)));
    })();
    """

    // MARK: 静的ファイル配信

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var rel = (url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path).removingPercentEncoding ?? url.path
        if rel.isEmpty { rel = "index.html" }
        // hyperbuf://project/* はプロジェクト内の画像だけを返す。それ以外(app)は web ディレクトリの静的ファイル。
        let isProject = url.host == "project"
        guard let file = contained(rel, in: isProject ? projectRoot : webRoot),
            !isProject || Host.imageExtensions.contains(file.pathExtension.lowercased()),
            let data = try? Data(contentsOf: file)
        else {
            let res = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            task.didReceive(res)
            task.didFinish()
            return
        }
        // 外部通信・インライン実行を禁じる(local first / 不信任入力の前提)
        let csp = "default-src hyperbuf:; script-src hyperbuf: 'wasm-unsafe-eval'; style-src hyperbuf: 'unsafe-inline'; font-src hyperbuf:; img-src hyperbuf:; connect-src hyperbuf:"
        // プロジェクトの画像は何も実行・読み込みさせない(SVG に含まれる script なども無効)
        let res = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: [
                "Content-Type": mime(file),
                "Content-Security-Policy": isProject ? "default-src 'none'; style-src 'unsafe-inline'" : csp,
                "X-Content-Type-Options": "nosniff",
                "Cache-Control": "no-store",
            ])!
        task.didReceive(res)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func mime(_ file: URL) -> String {
        switch file.pathExtension {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "wasm": return "application/wasm"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg"]

    // MARK: ブリッジ

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            return replyHandler(nil, "bad message")
        }
        switch op {
        case "list":
            replyHandler(markdownFiles(), nil)
        case "read":
            guard let path = body["path"] as? String, path.hasSuffix(".md"),
                let file = contained(path, in: projectRoot),
                let text = try? String(contentsOf: file, encoding: .utf8)
            else { return replyHandler(nil, "cannot read") }
            replyHandler(text, nil)
        case "search":
            guard let query = body["query"] as? String, !query.isEmpty else { return replyHandler(nil, "empty query") }
            let engine = body["engine"] as? String ?? "swift"
            let limit = body["limit"] as? Int ?? 200
            DispatchQueue.global(qos: .userInitiated).async {
                let result = engine == "rg" ? self.searchRg(query, limit: limit) : self.searchSwift(query, limit: limit)
                DispatchQueue.main.async { replyHandler(result, nil) }
            }
        default:
            replyHandler(nil, "unknown op")
        }
    }

    // ルート配下に収まるパスだけを許可する(.. や symlink による脱出を拒否)
    private func contained(_ rel: String, in root: URL) -> URL? {
        let file = root.appendingPathComponent(rel).resolvingSymlinksInPath().standardizedFileURL
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return file.path.hasPrefix(base + "/") ? file : nil
    }

    private func markdownFiles() -> [String] {
        let base = projectRoot.resolvingSymlinksInPath().path
        guard let e = FileManager.default.enumerator(
            at: projectRoot.resolvingSymlinksInPath(), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return [] }
        return e.compactMap { ($0 as? URL) }
            .filter { $0.pathExtension == "md" }
            .map { String($0.path.dropFirst(base.count + 1)) }
            .sorted()
    }

    // MARK: 外部更新の検知

    func startWatching() {
        stamps = currentStamps()
        // HYPERBUF_DEBUG=1 のとき、起動 3 秒後に画面下部の表示を標準出力へ出す(ブリッジ疎通の確認用)
        // HYPERBUF_DEBUG_EVAL=<JS ファイル> のとき、そのスクリプトを実行して結果を出力する(自動検証用)
        if let evalPath = ProcessInfo.processInfo.environment["HYPERBUF_DEBUG_EVAL"],
            let script = try? String(contentsOfFile: evalPath, encoding: .utf8)
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.webView?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value): print("EVAL:", value ?? "nil")
                    case .failure(let error): print("EVAL ERROR:", error)
                    }
                    fflush(stdout)
                    exit(0)
                }
            }
        }
        if ProcessInfo.processInfo.environment["HYPERBUF_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.webView?.evaluateJavaScript(
                    "document.getElementById('echo').textContent + ' | ' + document.querySelector('.win-header')?.textContent"
                ) { value, error in
                    print("DEBUG:", value ?? "nil", error.map { "\($0)" } ?? "")
                    fflush(stdout)
                }
            }
        }
        if ProcessInfo.processInfo.environment["HYPERBUF_WATCH"] == "poll" {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        } else {
            watcher = FSWatcher(root: projectRoot) { [weak self] paths in paths.forEach { self?.notifyChanged($0) } }
        }
    }

    private func currentStamps() -> [String: Date] {
        var out: [String: Date] = [:]
        for rel in markdownFiles() {
            if let f = contained(rel, in: projectRoot),
                let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            {
                out[rel] = d
            }
        }
        return out
    }

    private func poll() {
        let now = currentStamps()
        for (path, date) in now where stamps[path] != date {
            notifyChanged(path)
        }
        stamps = now
    }

    private func notifyChanged(_ path: String) {
        let json = String(data: try! JSONEncoder().encode(path), encoding: .utf8)!
        webView?.evaluateJavaScript("window.__hostChanged && window.__hostChanged(\(json))")
        // HYPERBUF_LOG_EVENTS=1: 通知を JS へ渡した時刻(epoch ミリ秒)を出力する(反応時間の計測用)
        if ProcessInfo.processInfo.environment["HYPERBUF_LOG_EVENTS"] != nil {
            print("EVENT \(path) \(Int(Date().timeIntervalSince1970 * 1000))")
            fflush(stdout)
        }
    }
}

// MARK: 全文検索(PoC: 自前実装と ripgrep の比較)

extension Host {
    private static func fold(_ b: UInt8) -> UInt8 { (b >= 65 && b <= 90) ? b + 32 : b }

    /// 大文字小文字を区別しない(ASCII のみ折り畳み)部分文字列検索。1 ファイルにつき最大 maxPerFile 行。
    private static func scan(_ data: Data, _ q: [UInt8], path: String, maxPerFile: Int = 3) -> [[String: Any]] {
        var found: [[String: Any]] = []
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            let n = p.count, m = q.count
            var i = 0, line = 1
            while i < n && found.count < maxPerFile {
                var e = i
                while e < n && p[e] != 10 { e += 1 }
                if e - i >= m {
                    var s = i
                    while s + m <= e {
                        var k = 0
                        while k < m && fold(p[s + k]) == q[k] { k += 1 }
                        if k == m {
                            let text = String(decoding: UnsafeBufferPointer(rebasing: p[i..<min(e, i + 200)]), as: UTF8.self)
                            found.append(["path": path, "line": line, "text": text])
                            break
                        }
                        s += 1
                    }
                }
                i = e + 1
                line += 1
            }
        }
        return found
    }

    func searchSwift(_ query: String, limit: Int) -> [String: Any] {
        let t0 = DispatchTime.now()
        let files = markdownFiles()
        let t1 = DispatchTime.now()
        let q = Array(query.utf8).map(Host.fold)
        let root = projectRoot.resolvingSymlinksInPath()
        var perFile = [[[String: Any]]](repeating: [], count: files.count)
        perFile.withUnsafeMutableBufferPointer { buf in
            let out = buf  // 各 index には 1 スレッドしか書かない
            DispatchQueue.concurrentPerform(iterations: files.count) { i in
                guard let data = try? Data(contentsOf: root.appendingPathComponent(files[i]), options: .mappedIfSafe)
                else { return }
                out[i] = Host.scan(data, q, path: files[i])
            }
        }
        let all = perFile.flatMap { $0 }
        let t2 = DispatchTime.now()
        return [
            "engine": "swift", "files": files.count, "total": all.count, "truncated": all.count > limit,
            "results": Array(all.prefix(limit)),
            "listMs": Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6,
            "scanMs": Double(t2.uptimeNanoseconds - t1.uptimeNanoseconds) / 1e6,
        ]
    }

    /// ripgrep を外部プロセスとして呼ぶ。クエリは引数として渡す(シェルを介さない)。
    func searchRg(_ query: String, limit: Int) -> [String: Any] {
        guard let rg = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"].first(where: FileManager.default.isExecutableFile)
        else { return ["error": "rg not found"] }
        let t0 = DispatchTime.now()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: rg)
        proc.currentDirectoryURL = projectRoot
        proc.arguments = [
            "--null", "--line-number", "--ignore-case", "--fixed-strings", "--max-count", "3", "--no-heading",
            "--color", "never", "-g", "*.md", "--", query, ".",
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return ["error": "\(error)"] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        var all: [[String: Any]] = []
        for row in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let nul = row.firstIndex(of: "\0") else { continue }
            let path = String(row[..<nul]).replacingOccurrences(of: "./", with: "", options: .anchored)
            let rest = row[row.index(after: nul)...]
            guard let colon = rest.firstIndex(of: ":"), let line = Int(rest[..<colon]) else { continue }
            all.append(["path": path, "line": line, "text": String(rest[rest.index(after: colon)...].prefix(200))])
        }
        let t1 = DispatchTime.now()
        return [
            "engine": "rg", "total": all.count, "truncated": all.count > limit, "results": Array(all.prefix(limit)),
            "listMs": 0.0, "scanMs": Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6,
        ]
    }
}
