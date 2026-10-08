import Foundation
import Testing

@testable import HyperBufProtocol

@Suite struct LocationTests {
    private func examples() throws -> [[String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("examples/location.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    /// スキーマに合う例は、型として読める。合わない例の一部(型が違うもの)は、読めない。
    @Test func validExamplesDecodeAndRoundTrip() throws {
        var decoded = 0
        for item in try examples() where item["valid"] as? Bool == true {
            let name = item["name"] as? String ?? "?"
            let data = try JSONSerialization.data(withJSONObject: try #require(item["location"], "\(name)"))
            let payload = try JSONDecoder().decode(LocationPayload.self, from: data)
            let again = try JSONDecoder().decode(LocationPayload.self, from: JSONEncoder().encode(payload))
            #expect(payload == again, "\(name)")
            decoded += 1
        }
        #expect(decoded >= 3)
    }

    @Test func invalidExamplesWithWrongShapesDoNotDecode() throws {
        for item in try examples() where item["valid"] as? Bool == false {
            let name = item["name"] as? String ?? "?"
            // 型として読めないもの(不正な precision、欠けた file)は、読めない。値の範囲(line が 0 など)は、スキーマ側の検査
            guard ["precision が不正", "file がない"].contains(name) else { continue }
            let data = try JSONSerialization.data(withJSONObject: try #require(item["location"]))
            #expect(throws: (any Error).self, "\(name)") { try JSONDecoder().decode(LocationPayload.self, from: data) }
        }
    }

    @Test func jsonValueKeepsTheSchemaFieldNames() throws {
        let payload = LocationPayload(
            path: "/a.md",
            range: .init(start: .init(line: 1, column: 2), end: .init(line: 1, column: 5)),
            precision: .exact, expect: "abc", expectTruncated: false,
            context: .init(before: "x", after: "y"),
            file: .init(sha256: String(repeating: "a", count: 64), mtime: 1, size: 3),
            viewer: .init(selection: "abc", version: 2, readAt: 5), markedAt: 9)
        guard case .object(let object) = payload.json else {
            Issue.record("オブジェクトになるはず")
            return
        }
        #expect(
            Set(object.keys) == [
                "v", "path", "range", "precision", "expect", "expectTruncated", "context", "file", "viewer", "markedAt",
            ])
        #expect(object["precision"] == .string("exact"))
        #expect(object["v"] == .number(1))
    }
}
