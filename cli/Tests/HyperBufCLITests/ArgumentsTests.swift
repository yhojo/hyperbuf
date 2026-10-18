// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufCLI

@Suite struct ArgumentsTests {
    private func open(_ args: [String]) throws -> OpenOptions {
        guard case .success(.open(let options)) = Arguments.parse(args) else { throw UsageError("open ではない") }
        return options
    }

    @Test func parsesHelpAndVersion() {
        #expect(Arguments.parse(["--help"]) == .success(.help))
        #expect(Arguments.parse(["-h"]) == .success(.help))
        #expect(Arguments.parse(["--version"]) == .success(.version))
        // ファイルの指定がなくても、--help は使える
        #expect(Arguments.parse(["a.md", "--help"]) == .success(.help))
    }

    @Test func parsesOptionsInAnyOrder() throws {
        let o = try open(["--wait", "a.md", "--anchor", "x", "--no-activate", "--print-url"])
        #expect(o.files == ["a.md"])
        #expect(o.anchor == "x")
        #expect(o.wait && o.noActivate && o.printURL)
    }

    @Test func keepsFileOrder() throws {
        #expect(try open(["a.md", "b.md", "c.md"]).files == ["a.md", "b.md", "c.md"])
    }

    @Test func doubleDashEndsOptions() throws {
        #expect(try open(["--", "--weird.md"]).files == ["--weird.md"])
    }

    @Test func rejectsBadUsage() {
        for bad: [String] in [
            [], ["--line"], ["--line", "x", "a.md"], ["--line", "0", "a.md"], ["--line", "-1", "a.md"],
            ["--target", "nowhere", "a.md"], ["--bogus", "a.md"], ["--line", "2", "a.md", "b.md"],
            ["--anchor", "x", "a.md", "b.md"], ["--project", "dir", "a.md"],
        ] {
            guard case .failure = Arguments.parse(bad) else {
                Issue.record("使い方の誤りになるはず: \(bad)")
                continue
            }
        }
    }
}
