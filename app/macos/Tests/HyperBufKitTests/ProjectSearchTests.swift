import Foundation
import Testing

@testable import HyperBufKit

@Suite struct ProjectSearchTests {
    private func search(_ files: [String: String], _ query: String, limit: Int = 200) throws -> SearchResponse {
        let t = try TempProject(files: files)
        defer { t.remove() }
        return ProjectSearch.search(Project(root: t.url), query: query, limit: limit)
    }

    @Test func findsAsciiCaseInsensitively() throws {
        let r = try search(["a.md": "Hello World\nnothing\nHELLO again\n"], "hello")
        #expect(r.results.map(\.line) == [1, 3])
        #expect(r.results.first?.text == "Hello World")
        #expect(r.results.first?.path == "a.md")
    }

    @Test func findsJapaneseExactly() throws {
        let r = try search(["a.md": "ハイパーバッファでの検索\n別の行\n"], "ハイパーバッファ")
        #expect(r.total == 1)
        #expect(r.results.first?.line == 1)
    }

    @Test func capsHitsPerFile() throws {
        let body = (1...10).map { "match \($0)" }.joined(separator: "\n")
        let r = try search(["a.md": body], "match")
        #expect(r.total == ProjectSearch.maxPerFile)
        #expect(r.results.map(\.line) == [1, 2, 3])
    }

    @Test func appliesLimitAndReportsTruncation() throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<10).map { ("f\($0).md", "needle\n") })
        let r = try search(files, "needle", limit: 4)
        #expect(r.results.count == 4)
        #expect(r.total == 10)
        #expect(r.truncated)
    }

    @Test func emptyQueryFindsNothing() throws {
        let r = try search(["a.md": "text\n"], "")
        #expect(r.total == 0)
        #expect(!r.truncated)
    }

    @Test func skipsExcludedDirectories() throws {
        let r = try search(["a.md": "x\n", "node_modules/p/README.md": "needle\n", ".hid/b.md": "needle\n"], "needle")
        #expect(r.total == 0)
    }

    @Test func handlesLastLineWithoutNewlineAndCRLF() throws {
        let r = try search(["a.md": "one\r\ntwo needle", "b.md": "needle\r\n"], "needle")
        #expect(Set(r.results.map(\.path)) == ["a.md", "b.md"])
        #expect(r.results.first { $0.path == "a.md" }?.line == 2)
    }

    @Test func truncatesLongLinesWithoutBreakingUtf8() throws {
        let long = String(repeating: "あ", count: 200) + " needle"
        let r = try search(["a.md": long + "\n"], "needle")
        // 該当は、200 バイトより後ろにあるので、行頭の 200 バイトの表示とは別に、見つかっている
        #expect(r.total == 1)
        #expect((r.results.first?.text.utf8.count ?? 0) <= 203)
    }
}
