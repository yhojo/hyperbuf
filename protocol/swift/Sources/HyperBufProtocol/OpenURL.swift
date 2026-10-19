// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// `hyperbuf://open?v=1&path=…&line=…&anchor=…&project=…&target=…`(docs/dev/integration-protocol.md §5.2)。
public enum OpenURL {
    public static func make(_ request: Request) -> URL? {
        var components = URLComponents()
        components.scheme = HyperBufProtocol.urlScheme
        // ping only launches the app (first launch of the CLI). Files are sent over the socket
        components.host = request.op == RequestOperation.ping.rawValue ? "ping" : "open"
        var items = [URLQueryItem(name: "v", value: String(request.v ?? HyperBufProtocol.version))]
        if let path = request.path { items.append(URLQueryItem(name: "path", value: path)) }
        if let line = request.line { items.append(URLQueryItem(name: "line", value: String(line))) }
        if let anchor = request.anchor { items.append(URLQueryItem(name: "anchor", value: anchor)) }
        if let project = request.project { items.append(URLQueryItem(name: "project", value: project)) }
        if let target = request.target { items.append(URLQueryItem(name: "target", value: target)) }
        components.queryItems = items
        return components.url
    }

    /// Builds a request from a URL. A URL whose operation is not `open` (except ping) is treated as an unknown
    /// operation.
    public static func parse(_ url: URL) -> Result<Request, ProtocolError> {
        guard url.scheme == HyperBufProtocol.urlScheme else {
            return .failure(ProtocolError(.badRequest, "Unsupported URL"))
        }
        guard let op = url.host.flatMap(RequestOperation.init(rawValue:)), op == .open || op == .ping else {
            return .failure(ProtocolError(.unknownOp, "Unsupported operation: \(url.host ?? "")"))
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        var request = Request(op: op)
        if let v = q["v"] {
            guard let n = Int(v) else { return .failure(ProtocolError(.badRequest, "Invalid v")) }
            request.v = n
        }
        request.path = q["path"]
        if let line = q["line"] {
            guard let n = Int(line) else { return .failure(ProtocolError(.badRequest, "Invalid line")) }
            request.line = n
        }
        request.anchor = q["anchor"]
        request.project = q["project"]
        request.target = q["target"]
        return .success(request)
    }
}
