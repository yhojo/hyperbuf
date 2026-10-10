import Foundation
import HyperBufKit
import WebKit

/// `hyperbuf://app/*`(Web コア)と、`hyperbuf://file/<絶対パス>`(文書が参照する画像)を配る。
/// 画像は、読み込みのたびに `FileAccess` が判定する(警告パスの画像は、404 になる。Web コアの判断を信用しない)。
/// file:// だと ES modules が読めないこと、ファイルアクセスの範囲を自分で管理したいことから、カスタムスキームを使う。
@MainActor
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let web: StaticFiles
    private let access: FileAccess

    init(web: StaticFiles, access: FileAccess) {
        self.web = web
        self.access = access
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        do {
            switch url.host {
            case "app":
                let relative = String(url.path.dropFirst())
                let file = try web.read(relative)
                respond(task, url: url, status: 200, mime: file.mime, csp: ContentSecurityPolicy.app, body: file.data)
            case "file":
                // `url.path` は、パーセントエンコードを戻した絶対パス
                let file = try access.readResource(url.path)
                respond(
                    task, url: url, status: 200, mime: file.mime, csp: ContentSecurityPolicy.resource, body: file.data)
            default:
                respond(
                    task, url: url, status: 404, mime: "text/plain", csp: ContentSecurityPolicy.resource, body: Data())
            }
        } catch {
            respond(task, url: url, status: 404, mime: "text/plain", csp: ContentSecurityPolicy.resource, body: Data())
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func respond(_ task: any WKURLSchemeTask, url: URL, status: Int, mime: String, csp: String, body: Data) {
        let headers = [
            "Content-Type": mime,
            "Content-Security-Policy": csp,
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "no-store",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
        else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
