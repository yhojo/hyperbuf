// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// `hyperbuf://open?v=1&path=…&line=…&anchor=…&project=…&target=…`(docs/integration-protocol.md §4.1)。
public enum OpenURL {
    public static func make(_ request: Request) -> URL? {
        var components = URLComponents()
        components.scheme = HyperBufProtocol.urlScheme
        // ping は、アプリの起動だけ(CLI の初回起動)。ファイルは、ソケットで送る
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

    /// URL から要求を作る。操作が `open` でない URL(ping を除く)は、未知の操作として扱う。
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
