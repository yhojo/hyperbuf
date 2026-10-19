// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct VCSBranchTests {
    private let hash = "0123456789abcdef0123456789abcdef01234567"

    private func branch(_ t: TempProject, _ sub: String) -> String? {
        VCSBranch.read(from: t.real + "/" + sub, home: t.real + "/home")
    }

    @Test func readsTheBranchName() throws {
        let t = try TempProject(files: ["repo/.git/HEAD": "ref: refs/heads/feat/x\n", "repo/docs/a.md": ""])
        defer { t.remove() }
        #expect(branch(t, "repo") == "feat/x")
        #expect(branch(t, "repo/docs") == "feat/x")
    }

    @Test func detachedHeadShowsAShortHash() throws {
        let t = try TempProject(files: ["repo/.git/HEAD": hash + "\n"])
        defer { t.remove() }
        #expect(branch(t, "repo") == "0123456")
    }

    @Test func followsGitdirFilesOfWorktrees() throws {
        let t = try TempProject(files: ["main/.git/worktrees/wt/HEAD": "ref: refs/heads/topic\n"])
        try t.write("wt/.git", "gitdir: \(t.real)/main/.git/worktrees/wt\n")
        defer { t.remove() }
        #expect(branch(t, "wt") == "topic")
    }

    @Test func relativeGitdirIsResolvedAgainstTheRoot() throws {
        let t = try TempProject(files: [
            "sub/.git": "gitdir: ../mod-git\n", "mod-git/HEAD": "ref: refs/heads/dev\n",
        ])
        defer { t.remove() }
        #expect(branch(t, "sub") == "dev")
    }

    @Test func nothingWithoutAGitRootOrAReadableHead() throws {
        let t = try TempProject(files: [
            "plain/a.md": "", "hg/.hg/branch": "default", "empty/.git/x": "", "junk/.git/HEAD": "hello\n",
            "bad/.git": "not a gitdir line\n",
        ])
        defer { t.remove() }
        for sub in ["plain", "hg", "empty", "junk", "bad"] { #expect(branch(t, sub) == nil) }
    }

    @Test func rejectsControlCharactersAndTruncatesLongNames() {
        #expect(VCSBranch.parse("ref: refs/heads/a\u{1b}[31mb\n") == nil)
        let long = String(repeating: "a", count: 200)
        let shown = VCSBranch.parse("ref: refs/heads/\(long)\n")
        #expect(shown?.count == VCSBranch.maxLength && shown?.hasSuffix("…") == true)
        #expect(VCSBranch.parse("ref: refs/remotes/o/x\n") == "remotes/o/x")
        #expect(VCSBranch.parse("ref: refs/heads/\n") == nil)
    }

    @Test func readsOnlyTheFirstLine() {
        #expect(VCSBranch.parse("ref: refs/heads/main\nignored\n") == "main")
    }
}
