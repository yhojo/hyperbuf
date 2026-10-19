// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufProtocol

/// Reads the examples in protocol/examples/. The same examples are shared by Swift, the CLI, Emacs and Node (JSON
/// Schema).
private func example(_ name: String) throws -> [[String: Any]] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("examples/\(name).json")
    let data = try Data(contentsOf: url)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}

private func decodeRequest(_ object: [String: Any]) throws -> Request {
    try JSONDecoder().decode(Request.self, from: JSONSerialization.data(withJSONObject: object))
}

@Suite struct ConformanceTests {
    @Test func openValidation() throws {
        for item in try example("open-validation") {
            let name = item["name"] as? String ?? "?"
            let request = try decodeRequest(try #require(item["request"] as? [String: Any]))
            let result = OpenRequestValidator.validate(
                path: request.path, line: request.line, anchor: request.anchor, version: request.v)
            switch (item["expect"] as? String, result) {
            case ("ok", .success): break
            case (let expected?, .failure(let error)) where expected != "ok": #expect(error.code == expected, "\(name)")
            default: Issue.record("\(name): expected \(item["expect"] ?? "?"), got \(result)")
            }
        }
    }

    @Test func urls() throws {
        for item in try example("url") {
            let name = item["name"] as? String ?? "?"
            let urlString = try #require(item["url"] as? String, "\(name)")
            let url = try #require(URL(string: urlString), "\(name)")
            let result = OpenURL.parse(url)
            if let expected = item["error"] as? String {
                guard case .failure(let error) = result else {
                    Issue.record("\(name): 失敗するはず")
                    continue
                }
                #expect(error.code == expected, "\(name)")
            } else {
                let expected = try decodeRequest(try #require(item["request"] as? [String: Any]))
                guard case .success(let parsed) = result else {
                    Issue.record("\(name): 成功するはず")
                    continue
                }
                #expect(parsed.op == expected.op, "\(name)")
                #expect(parsed.path == expected.path, "\(name)")
                #expect(parsed.line == expected.line, "\(name)")
                #expect(parsed.anchor == expected.anchor, "\(name)")
                // Reading the built URL again yields the same request
                if expected.op == RequestOperation.open.rawValue {
                    let rebuilt = try #require(OpenURL.make(expected), "\(name)")
                    guard case .success(let again) = OpenURL.parse(rebuilt) else {
                        Issue.record("\(name): 往復")
                        continue
                    }
                    #expect(
                        again.path == expected.path && again.line == expected.line && again.anchor == expected.anchor,
                        "\(name)")
                }
            }
        }
    }

    @Test func framing() throws {
        for item in try example("framing") {
            let name = item["name"] as? String ?? "?"
            var framer = LineFramer()
            var lines: [String] = []
            for chunk in try #require(item["chunks"] as? [String]) {
                lines += try framer.append(Data(chunk.utf8)).map { String(decoding: $0, as: UTF8.self) }
            }
            #expect(lines == item["lines"] as? [String], "\(name)")
        }
    }
}
