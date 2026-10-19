// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufKit

@Suite struct OpenClassifierTests {
    private func open(_ path: String) -> ValidatedOpen {
        guard case .success(let v) = OpenRequestValidator.validate(path: path, line: nil, anchor: nil, version: nil)
        else { fatalError("validation failed: \(path)") }
        return v
    }

    private func classify(
        _ path: String, _ t: TempProject, warn: [String] = [], allow: [String] = [], viaURL: Bool = false
    ) -> Result<OpenClassifier.Outcome, ProtocolError> {
        OpenClassifier.classify(
            open(path), policy: PathPolicy(home: t.real, warn: warn, allow: allow),
            remembered: RememberedPaths(url: t.url.appendingPathComponent("state/r.json")),
            alwaysConfirmUnlessAllowed: viaURL)
    }

    @Test func opensFilesOutsideTheWarnPaths() throws {
        let t = try TempProject(files: ["a.md": "x"])
        defer { t.remove() }
        #expect(try classify(t.url.path + "/a.md", t).get() == .open(absolute: t.real + "/a.md"))
    }

    @Test func missingFilesFail() throws {
        let t = try TempProject()
        defer { t.remove() }
        guard case .failure(let error) = classify(t.url.path + "/none.md", t) else {
            Issue.record("should fail")
            return
        }
        #expect(error.code == ErrorCode.notFound.rawValue)
    }

    @Test func warnPathsNeedConfirmationWithAProposal() throws {
        let t = try TempProject(files: ["w/sub/a.md": "x"])
        defer { t.remove() }
        let outcome = try classify(t.url.path + "/w/sub/a.md", t, warn: [t.real + "/w"]).get()
        #expect(outcome == .confirm(absolute: t.real + "/w/sub/a.md", remember: t.real + "/w/sub"))
    }

    @Test func symlinksAreResolvedBeforeJudging() throws {
        let t = try TempProject(files: ["w/a.md": "x", "ok/.keep": ""])
        defer { t.remove() }
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("ok/link.md"), withDestinationURL: t.url.appendingPathComponent("w/a.md"))
        let outcome = try classify(t.url.path + "/ok/link.md", t, warn: [t.real + "/w"]).get()
        guard case .confirm(let absolute, _) = outcome else {
            Issue.record("the real path of a warn path needs confirmation")
            return
        }
        #expect(absolute == t.real + "/w/a.md")
    }

    @Test func urlSchemeConfirmsEverythingExceptExplicitlyAllowedPaths() throws {
        let t = try TempProject(files: ["docs/a.md": "x", "other/b.md": "x"])
        defer { t.remove() }
        // Inside an allow path (allowPaths) no confirmation. Anything else is confirmed even outside the warn paths
        #expect(
            try classify(t.url.path + "/docs/a.md", t, allow: [t.real + "/docs"], viaURL: true).get()
                == .open(absolute: t.real + "/docs/a.md"))
        let other = try classify(t.url.path + "/other/b.md", t, allow: [t.real + "/docs"], viaURL: true).get()
        #expect(other == .confirm(absolute: t.real + "/other/b.md", remember: t.real + "/other"))
        // Via the socket, the same file needs no confirmation
        #expect(try classify(t.url.path + "/other/b.md", t).get() == .open(absolute: t.real + "/other/b.md"))
    }
}
