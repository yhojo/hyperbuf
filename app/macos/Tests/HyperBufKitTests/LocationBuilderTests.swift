// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufKit

@Suite struct LocationBuilderTests {
    private func web(path: String, precision: LocationPayload.Precision = .exact) -> WebLocation {
        let json = """
            {"path": \(String(reflecting: path)), "range": {"start": {"line": 1, "column": 3}, "end": {"line": 1, "column": 6}},
             "precision": "\(precision.rawValue)", "expect": "abc", "expectTruncated": false,
             "context": {"before": "x ", "after": " y"}, "selection": "abc", "version": 4}
            """
        // JSON のエスケープは、JSONSerialization に任せる
        let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return (try? JSONDecoder().decode(WebLocation.self, from: data))!
    }

    private func access(_ t: TempProject) -> FileAccess {
        FileAccess(
            policy: PathPolicy(home: t.real, warn: [], allow: []),
            remembered: RememberedPaths(url: t.url.appendingPathComponent("state/r.json")))
    }

    @Test func buildsAnAbsolutePathAndFileFingerprint() throws {
        let t = try TempProject(files: ["docs/a.md": "x abc y\n"])
        defer { t.remove() }
        let access = access(t)
        let path = t.url.path + "/docs/a.md"
        _ = try access.readMarkdown(path)  // ビューアが読んだ版

        let now = Date(timeIntervalSince1970: 1000)
        let payload = try LocationBuilder.build(web(path: path), access: access, now: now).get()
        #expect(payload.path == t.real + "/docs/a.md")
        #expect(payload.file.sha256 == FileFingerprint.sha256Hex(Data("x abc y\n".utf8)))
        #expect(payload.file.size == 8)
        #expect(payload.viewer.version == 4 && payload.viewer.selection == "abc")
        #expect(payload.markedAt == 1_000_000)
        #expect(payload.precision == .exact)
        #expect(payload.range.start == .init(line: 1, column: 3))
        #expect(payload.v == 1)
    }

    @Test func rejectsRelativeAndMissingPaths() throws {
        let t = try TempProject(files: ["a.md": "x"])
        defer { t.remove() }
        let access = access(t)
        for bad in ["a.md", t.url.path + "/none.md", "*search: x*"] {
            guard case .failure(let error) = LocationBuilder.build(web(path: bad), access: access) else {
                Issue.record("拒否されるはず: \(bad)")
                continue
            }
            #expect(error.code == ErrorCode.notFound.rawValue)
        }
    }

    @Test func withoutAReadRecordTheVersionIsUnknown() throws {
        let t = try TempProject(files: ["a.md": "x abc y"])
        defer { t.remove() }
        let result = LocationBuilder.build(web(path: t.url.path + "/a.md"), access: access(t))
        guard case .failure(let error) = result else {
            Issue.record("読んだ記録がなければ、渡さない")
            return
        }
        #expect(error.code == ErrorCode.stale.rawValue)
    }

    @Test func nonMarkdownIsRefused() throws {
        let t = try TempProject(files: ["a.txt": "x"])
        defer { t.remove() }
        guard case .failure(let error) = LocationBuilder.build(web(path: t.url.path + "/a.txt"), access: access(t))
        else {
            Issue.record("拒否されるはず")
            return
        }
        #expect(error.code == ErrorCode.notMarkdown.rawValue)
    }
}
