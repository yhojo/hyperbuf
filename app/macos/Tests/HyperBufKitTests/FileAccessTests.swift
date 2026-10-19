// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct FileAccessTests {
    private func access(_ t: TempProject, warn: [String] = [], allow: [String] = []) -> FileAccess {
        FileAccess(
            policy: PathPolicy(home: t.real, warn: warn, allow: allow),
            remembered: RememberedPaths(url: t.url.appendingPathComponent("state/r.json")))
    }

    @Test func readsAbsoluteMarkdown() throws {
        let t = try TempProject(files: ["docs/a.md": "# A\n"])
        defer { t.remove() }
        #expect(try access(t).readMarkdown(t.url.path + "/docs/a.md") == "# A\n")
    }

    @Test func rejectsRelativeTraversalAndNul() throws {
        let t = try TempProject(files: ["a.md": "x"])
        defer { t.remove() }
        let a = access(t)
        #expect(throws: AccessError.invalidPath) { try a.readMarkdown("a.md") }
        #expect(throws: AccessError.invalidPath) { try a.readMarkdown(t.url.path + "/../a.md") }
        #expect(throws: AccessError.invalidPath) { try a.readMarkdown(t.url.path + "/a.md\0.md") }
        #expect(throws: AccessError.notFound) { try a.readMarkdown(t.url.path + "/none.md") }
        #expect(throws: AccessError.notMarkdown) { try a.readMarkdown(t.url.path + "/a.txt") }
    }

    @Test func markdownReadingDoesNotJudgeTheWarnPaths() throws {
        // Paths the user typed or chose, already-judged external requests and restored sessions are read without judging
        let t = try TempProject(files: ["w/a.md": "warned"])
        defer { t.remove() }
        let a = access(t, warn: [t.real + "/w"])
        #expect(try a.readMarkdown(t.url.path + "/w/a.md") == "warned")
        #expect(try a.decide(t.url.path + "/w/a.md") != .allow)
    }

    @Test func aSymlinkToANonMarkdownTargetIsRefused() throws {
        let t = try TempProject(files: ["secret.txt": "s", "ok.md": "ok"])
        defer { t.remove() }
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("link.md"), withDestinationURL: t.url.appendingPathComponent("secret.txt"))
        let a = access(t)
        #expect(throws: AccessError.notMarkdown) { try a.readMarkdown(t.url.path + "/link.md") }
    }

    @Test func recordsFingerprints() throws {
        let t = try TempProject(files: ["a.md": "abc"])
        defer { t.remove() }
        let a = access(t)
        _ = try a.readMarkdown(t.url.path + "/a.md")
        #expect(a.fingerprints.get(t.real + "/a.md")?.size == 3)
    }

    @Test func resourcesAreJudgedAndOnlyImages() throws {
        let t = try TempProject(files: ["img/p.png": "PNG", "w/q.png": "PNG", "n.txt": "x"])
        defer { t.remove() }
        let a = access(t, warn: [t.real + "/w"])
        let ok = try a.readResource(t.url.path + "/img/p.png")
        #expect(ok.mime == "image/png")
        #expect(throws: AccessError.needsConfirmation) { try a.readResource(t.url.path + "/w/q.png") }
        #expect(throws: AccessError.unsupportedResource) { try a.readResource(t.url.path + "/n.txt") }
        #expect(throws: AccessError.invalidPath) { try a.readResource("img/p.png") }
    }

    @Test func rememberedPathsAllowResources() throws {
        let t = try TempProject(files: ["w/q.png": "PNG"])
        defer { t.remove() }
        let a = access(t, warn: [t.real + "/w"])
        #expect(a.remembered.add(t.real + "/w"))
        #expect(try a.readResource(t.url.path + "/w/q.png").mime == "image/png")
    }
}
