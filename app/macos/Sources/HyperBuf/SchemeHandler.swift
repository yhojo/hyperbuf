// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufKit
import WebKit

/// Serves `hyperbuf://app/*` (the Web core) and `hyperbuf://file/<absolute path>` (images referenced by documents).
/// `FileAccess` judges images on every load (an image under a warn path gets a 404; the Web core's judgment is not trusted).
/// A custom scheme is used because ES modules cannot be loaded over file:// and the file access scope must be managed by us.
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
                // `url.path` is the absolute path with percent-encoding decoded
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
