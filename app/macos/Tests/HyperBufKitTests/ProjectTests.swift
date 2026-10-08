import Foundation
import Testing

@testable import HyperBufKit

@Suite struct ProjectTests {
    @Test func listsMarkdownRecursivelyAndSorted() throws {
        let t = try TempProject(files: ["b.md": "", "a.md": "", "sub/c.md": "", "sub/deep/d.md": "", "x.txt": ""])
        defer { t.remove() }
        #expect(Project(root: t.url).markdownFiles() == ["a.md", "b.md", "sub/c.md", "sub/deep/d.md"])
    }

    @Test func excludesHiddenEntriesAndNodeModules() throws {
        let t = try TempProject(files: [
            "a.md": "", ".hidden.md": "", ".git/x.md": "", "node_modules/pkg/README.md": "",
            "sub/node_modules/pkg/README.md": "", "sub/ok.md": "",
        ])
        defer { t.remove() }
        #expect(Project(root: t.url).markdownFiles() == ["a.md", "sub/ok.md"])
    }

    @Test func readsMarkdown() throws {
        let t = try TempProject(files: ["a.md": "# 見出し\n"])
        defer { t.remove() }
        #expect(try Project(root: t.url).readMarkdown("a.md") == "# 見出し\n")
    }

    @Test func rejectsPathsOutsideTheRoot() throws {
        let t = try TempProject(files: ["a.md": ""])
        defer { t.remove() }
        let p = Project(root: t.url)
        for bad in ["../a.md", "sub/../../a.md", "/etc/hosts", "", "a\u{0}.md", "a\n.md"] {
            #expect(throws: ProjectError.outside, "\(bad.debugDescription)") { try p.resolve(bad) }
        }
    }

    @Test func rejectsSymlinkThatEscapesTheRoot() throws {
        let outside = try TempProject(files: ["secret.md": "secret"])
        let t = try TempProject(files: ["a.md": ""])
        defer {
            outside.remove()
            t.remove()
        }
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("link.md"),
            withDestinationURL: outside.url.appendingPathComponent("secret.md"))
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("dir"), withDestinationURL: outside.url)
        let p = Project(root: t.url)
        #expect(throws: ProjectError.outside) { try p.readMarkdown("link.md") }
        #expect(throws: ProjectError.outside) { try p.readMarkdown("dir/secret.md") }
    }

    @Test func allowsSymlinkThatStaysInsideTheRoot() throws {
        let t = try TempProject(files: ["real/a.md": "inside"])
        defer { t.remove() }
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("alias.md"), withDestinationURL: t.url.appendingPathComponent("real/a.md"))
        #expect(try Project(root: t.url).readMarkdown("alias.md") == "inside")
    }

    @Test func readMarkdownRequiresMdExtensionAndExistence() throws {
        let t = try TempProject(files: ["a.txt": "", "b.md": ""])
        defer { t.remove() }
        let p = Project(root: t.url)
        #expect(throws: ProjectError.notMarkdown) { try p.readMarkdown("a.txt") }
        #expect(throws: ProjectError.notFound) { try p.readMarkdown("missing.md") }
    }

    @Test func readsOnlyImageResources() throws {
        let t = try TempProject(files: ["img/a.svg": "<svg/>", "img/b.png": "x", "note.md": "", "script.js": ""])
        defer { t.remove() }
        let p = Project(root: t.url)
        let svg = try p.readResource("img/a.svg")
        #expect(svg.mime == "image/svg+xml")
        #expect(try p.readResource("img/b.png").mime == "image/png")
        #expect(throws: ProjectError.unsupportedResource) { try p.readResource("note.md") }
        #expect(throws: ProjectError.unsupportedResource) { try p.readResource("script.js") }
        #expect(throws: ProjectError.outside) { try p.readResource("../x.png") }
    }

    @Test func handlesJapaneseFileNamesInEitherUnicodeForm() throws {
        // APFS は、NFC/NFD の違いを区別せずに引ける。どちらの形で来ても開けること。
        let nfc = "ハイパーバッファ.md"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        // Swift の String は正規等価なら等しいので、バイト列で、本当に違う形であることを確かめる
        #expect(Array(nfc.utf8) != Array(nfd.utf8))
        let t = try TempProject(files: [nfc: "本文"])
        defer { t.remove() }
        let p = Project(root: t.url)
        #expect(p.markdownFiles().count == 1)
        #expect(try p.readMarkdown(nfc) == "本文")
        #expect(try p.readMarkdown(nfd) == "本文")
    }
}
