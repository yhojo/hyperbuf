import Foundation
import Testing

@testable import HyperBufKit

@Suite struct TreeSearchTests {
    private func search(_ files: [String: String], _ query: String, limit: Int = 200) throws -> (SearchResponse, String)
    {
        let t = try TempProject(files: files)
        defer { t.remove() }
        return (TreeSearch.search(dir: t.url.path, home: "/nonexistent-home", query: query, limit: limit), t.real)
    }

    @Test func findsAsciiCaseInsensitivelyWithAbsolutePaths() throws {
        let (r, root) = try search(["a.md": "Hello World\nnothing\nHELLO again\n"], "hello")
        #expect(r.results.map(\.line) == [1, 3])
        #expect(r.results.first?.text == "Hello World")
        #expect(r.results.first?.path == root + "/a.md")
    }

    @Test func findsJapaneseExactly() throws {
        let (r, _) = try search(["a.md": "ハイパーバッファでの検索\n別の行\n"], "ハイパーバッファ")
        #expect(r.total == 1)
        #expect(r.results.first?.line == 1)
    }

    @Test func capsHitsPerFile() throws {
        let body = (1...10).map { "match \($0)" }.joined(separator: "\n")
        let (r, _) = try search(["a.md": body], "match")
        #expect(r.total == TreeSearch.maxPerFile)
        #expect(r.results.map(\.line) == [1, 2, 3])
    }

    @Test func appliesLimitAndReportsTruncation() throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<10).map { ("f\($0).md", "needle\n") })
        let (r, _) = try search(files, "needle", limit: 4)
        #expect(r.results.count == 4)
        #expect(r.total == 10)
        #expect(r.truncated)
    }

    @Test func emptyQueryFindsNothing() throws {
        let (r, _) = try search(["a.md": "text\n"], "")
        #expect(r.total == 0)
        #expect(!r.truncated)
    }

    @Test func skipsExcludedDirectories() throws {
        let (r, _) = try search(
            ["a.md": "x\n", "node_modules/p/README.md": "needle\n", ".hid/b.md": "needle\n"], "needle")
        #expect(r.total == 0)
    }

    @Test func searchesOnlyBelowTheGivenDirectory() throws {
        let t = try TempProject(files: ["top.md": "needle\n", "sub/in.md": "needle\n"])
        defer { t.remove() }
        let r = TreeSearch.search(dir: t.url.path + "/sub", home: "/x", query: "needle")
        #expect(r.results.map(\.path) == [t.real + "/sub/in.md"])
    }

    @Test func refusesHomeAndRoot() throws {
        let t = try TempProject(files: ["a.md": "needle\n"])
        defer { t.remove() }
        let r = TreeSearch.search(dir: t.url.path, home: t.real, query: "needle")
        #expect(r.refused != nil && r.total == 0)
        #expect(TreeSearch.search(dir: "/", home: t.real, query: "needle").refused != nil)
    }

    @Test func handlesLastLineWithoutNewlineAndCRLF() throws {
        let (r, root) = try search(["a.md": "one\r\ntwo needle", "b.md": "needle\r\n"], "needle")
        #expect(Set(r.results.map(\.path)) == [root + "/a.md", root + "/b.md"])
        #expect(r.results.first { $0.path == root + "/a.md" }?.line == 2)
    }
}
