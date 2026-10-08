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
      };
      window.__hostChanged = (path) => cbs.forEach((cb) => cb(path));
    })();
    """

    // MARK: 静的ファイル配信

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var rel = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        if rel.isEmpty { rel = "index.html" }
        guard let file = contained(rel, in: webRoot), let data = try? Data(contentsOf: file) else {
            let res = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            task.didReceive(res)
            task.didFinish()
            return
        }
        // 外部通信・インライン実行を禁じる(local first / 不信任入力の前提)
        let csp = "default-src hyperbuf:; style-src hyperbuf: 'unsafe-inline'; img-src hyperbuf: data:; connect-src 'none'"
        let res = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": mime(file), "Content-Security-Policy": csp, "Cache-Control": "no-store"])!
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
        default: return "application/octet-stream"
        }
    }

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
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
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
            let json = String(data: try! JSONEncoder().encode(path), encoding: .utf8)!
            webView?.evaluateJavaScript("window.__hostChanged && window.__hostChanged(\(json))")
        }
        stamps = now
    }
}
