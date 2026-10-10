import Foundation
import Testing

@testable import HyperBufKit

@Suite struct DirectoryListerTests {
    @Test func listsMarkdownAndDirectoriesOnly() throws {
        let t = try TempProject(files: [
            "a.md": "x", "note.txt": "x", "sub/b.md": "x", ".hidden.md": "x", ".hid/c.md": "x",
            "node_modules/p/d.md": "x",
        ])
        defer { t.remove() }
        let listing = DirectoryLister.list(t.url.path)
        let names = Set(listing.entries.map { "\($0.name)\($0.dir ? "/" : "")" })
        #expect(names == ["a.md", "sub/"])
        #expect(!listing.truncated)
    }

    @Test func hiddenEntriesAppearOnlyWhenAsked() throws {
        let t = try TempProject(files: [".hidden.md": "x", ".hid/c.md": "x", "a.md": "x"])
        defer { t.remove() }
        let names = Set(DirectoryLister.list(t.url.path, hidden: true).entries.map(\.name))
        #expect(names == [".hidden.md", ".hid", "a.md"])
    }

    @Test func truncatesAtTheLimitAndReportsErrors() throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<10).map { ("f\($0).md", "x") })
        let t = try TempProject(files: files)
        defer { t.remove() }
        let listing = DirectoryLister.list(t.url.path, limit: 4)
        #expect(listing.entries.count == 4 && listing.truncated)
        #expect(DirectoryLister.list("/no/such/dir").error != nil)
    }

    @Test func treeIsRecursiveSortedAndRelative() throws {
        let t = try TempProject(files: [
            "b.md": "x", "a/z.md": "x", "a/y/w.md": "x", "n.txt": "x", "node_modules/p/q.md": "x", ".h/h.md": "x",
        ])
        defer { t.remove() }
        let tree = DirectoryLister.tree(t.url.path, home: "/nonexistent-home")
        #expect(tree.files == ["a/y/w.md", "a/z.md", "b.md"])
        #expect(tree.refused == nil && !tree.truncated)
    }

    @Test func treeRefusesHomeAndRoot() throws {
        let t = try TempProject(files: ["a.md": "x"])
        defer { t.remove() }
        #expect(DirectoryLister.tree(t.url.path, home: t.real).refused != nil)
        #expect(DirectoryLister.tree("/", home: t.real).refused != nil)
        #expect(DirectoryLister.tree(t.url.appendingPathComponent("sub").path, home: t.real).error != nil)
    }

    @Test func treeStopsAtFileAndTimeLimits() throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<20).map { ("d/f\($0).md", "x") })
        let t = try TempProject(files: files)
        defer { t.remove() }
        let byCount = DirectoryLister.tree(t.url.path, home: "/x", maxFiles: 5)
        #expect(byCount.files.count == 5 && byCount.truncated)
        let byTime = DirectoryLister.tree(t.url.path, home: "/x", maxSeconds: -1)
        #expect(byTime.truncated)
    }

    @Test func treeDoesNotFollowSymlinkedDirectories() throws {
        let t = try TempProject(files: ["real/a.md": "x"])
        defer { t.remove() }
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("link"), withDestinationURL: t.url.appendingPathComponent("real"))
        let tree = DirectoryLister.tree(t.url.path, home: "/x")
        #expect(tree.files == ["real/a.md"])
    }
}
