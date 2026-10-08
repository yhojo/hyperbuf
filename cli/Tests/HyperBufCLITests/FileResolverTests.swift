import Foundation
import Testing

@testable import HyperBufCLI

@Suite struct FileResolverTests {
    @Test func resolvesRelativeAndSplitsLine() throws {
        let t = try TempDir()
        defer { t.remove() }
        try t.write("docs/a.md", "x")
        let r = try FileResolver.resolve("docs/a.md:42", cwd: t.path).get()
        #expect(r == FileResolver.Resolved(path: t.path + "/docs/a.md", line: 42))
        #expect(try FileResolver.resolve("docs/a.md:42:7", cwd: t.path).get().line == 42)
        #expect(try FileResolver.resolve("docs/a.md", cwd: t.path).get().line == nil)
    }

    @Test func existingFileNamedLikeALineSuffixWins() throws {
        let t = try TempDir()
        defer { t.remove() }
        try t.write("weird:12.md", "x")  // 名前そのものが存在するファイル
        let r = try FileResolver.resolve("weird:12.md", cwd: t.path).get()
        #expect(r.path == t.path + "/weird:12.md")
        #expect(r.line == nil)
    }

    @Test func rejectsMissingDirectoriesAndNonMarkdown() throws {
        let t = try TempDir()
        defer { t.remove() }
        try t.write("a.txt", "x")
        try t.write("dir/b.md", "x")
        for bad in ["missing.md", "a.txt", "dir", "a.md:3"] {
            guard case .failure = FileResolver.resolve(bad, cwd: t.path) else {
                Issue.record("失敗するはず: \(bad)")
                continue
            }
        }
    }

    @Test func resolvesDotsLexicallyWithoutFollowingSymlinks() throws {
        let t = try TempDir()
        defer { t.remove() }
        try t.write("real/a.md", "x")
        try FileManager.default.createSymbolicLink(
            atPath: t.path + "/link", withDestinationPath: t.path + "/real")
        // シンボリックリンクは、解決しない(アプリ側が、解決後の位置で、範囲を判定する)
        let r = try FileResolver.resolve("link/a.md", cwd: t.path).get()
        #expect(r.path == t.path + "/link/a.md")
    }
}
