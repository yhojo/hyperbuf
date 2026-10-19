// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct PathPolicyTests {
    /// Makes a temporary directory the host and creates warn paths and allow paths under it.
    private func fixture(_ files: [String: String] = [:]) throws -> (TempProject, RememberedPaths) {
        let t = try TempProject(files: files)
        return (t, RememberedPaths(url: t.url.appendingPathComponent("state/remembered.json")))
    }

    @Test func noMatchOpens() throws {
        let (t, r) = try fixture(["Downloads/foo/a.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: ["/usr"], allow: [])
        #expect(policy.decide(t.real + "/Downloads/foo/a.md", remembered: r) == .allow)
    }

    @Test func warnPathConfirmsAndProposesTheDirectory() throws {
        let (t, r) = try fixture(["vendor/pkg/a.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [t.real + "/vendor"], allow: [])
        let file = t.real + "/vendor/pkg/a.md"
        #expect(policy.decide(file, remembered: r) == .confirm(remember: t.real + "/vendor/pkg"))
    }

    @Test func longestMatchWins() throws {
        let (t, r) = try fixture(["vendor/ok/a.md": "x", "vendor/b.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [t.real + "/vendor"], allow: [t.real + "/vendor/ok"])
        #expect(policy.decide(t.real + "/vendor/ok/a.md", remembered: r) == .allow)
        #expect(policy.decide(t.real + "/vendor/b.md", remembered: r) != .allow)
        // Conversely: a more specific warn inside an allow
        let policy2 = PathPolicy(home: t.real, warn: [t.real + "/vendor/ok"], allow: [t.real + "/vendor"])
        #expect(policy2.decide(t.real + "/vendor/ok/a.md", remembered: r) != .allow)
        #expect(policy2.decide(t.real + "/vendor/b.md", remembered: r) == .allow)
    }

    @Test func samePathInBothIsWarnedAndReported() throws {
        let (t, r) = try fixture(["x/a.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [t.real + "/x"], allow: [t.real + "/x"])
        #expect(policy.decide(t.real + "/x/a.md", remembered: r) != .allow)
        #expect(policy.problems.count == 1)
    }

    @Test func matchesOnPathBoundaries() throws {
        let (t, r) = try fixture(["tmp2/a.md": "x", "tmp/a.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [t.real + "/tmp"], allow: [])
        #expect(policy.decide(t.real + "/tmp2/a.md", remembered: r) == .allow)
        #expect(policy.decide(t.real + "/tmp/a.md", remembered: r) != .allow)
    }

    @Test func rememberedPathsActAsAllowAndAreMoreSpecific() throws {
        let (t, r) = try fixture(["vendor/pkg/a.md": "x", "vendor/other/b.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [t.real + "/vendor"], allow: [])
        #expect(r.add(t.real + "/vendor/pkg"))
        #expect(policy.decide(t.real + "/vendor/pkg/a.md", remembered: r) == .allow)
        #expect(policy.decide(t.real + "/vendor/other/b.md", remembered: r) != .allow)
    }

    @Test func rememberingIsLimitedToTheFileWhenItWouldAllowAWarnPath() throws {
        let (t, r) = try fixture(["tmp/x.md": "x", "tmp/sub/y.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [t.real + "/tmp"], allow: [])
        // The file's directory is the warn path itself -> a single file, so the whole directory is not allowed
        #expect(policy.decide(t.real + "/tmp/x.md", remembered: r) == .confirm(remember: t.real + "/tmp/x.md"))
        // A subdirectory under a warn path -> the directory
        #expect(policy.decide(t.real + "/tmp/sub/y.md", remembered: r) == .confirm(remember: t.real + "/tmp/sub"))
        // A file in an ancestor directory of a warn path is also a single file
        let wide = PathPolicy(home: t.real, warn: [t.real + "/tmp/sub"], allow: [])
        #expect(wide.rememberTarget(for: t.real + "/tmp/z.md") == t.real + "/tmp/z.md")
    }

    @Test func explicitAllowIgnoresWarnPaths() throws {
        let (t, r) = try fixture(["docs/a.md": "x", "other/b.md": "x"])
        defer { t.remove() }
        let policy = PathPolicy(home: t.real, warn: [], allow: [t.real + "/docs"])
        #expect(policy.isExplicitlyAllowed(t.real + "/docs/a.md", remembered: r))
        #expect(!policy.isExplicitlyAllowed(t.real + "/other/b.md", remembered: r))
    }

    @Test func defaultsWarnSensitiveHomeFoldersAndAllowICloudDrive() throws {
        let (t, r) = try fixture()
        defer { t.remove() }
        let home = t.real
        // The temporary directory is under `/var`, so use only the defaults under the host (system warn paths are checked separately)
        let policy = PathPolicy(
            home: home, warn: PathPolicy.defaultWarn(home: home).filter { $0.hasPrefix(home + "/") })
        #expect(policy.decide(home + "/.ssh/notes.md", remembered: r) != .allow)
        #expect(policy.decide(home + "/Library/Mail/x.md", remembered: r) != .allow)
        #expect(policy.decide(home + "/Library/Mobile Documents/com~apple~CloudDocs/a.md", remembered: r) == .allow)
        #expect(policy.decide(home + "/Documents/a.md", remembered: r) == .allow)
        #expect(PathPolicy(home: home).decide("/usr/share/doc/a.md", remembered: r) != .allow)
    }

    @Test func loadsConfigAndReportsProblems() throws {
        let t = try TempProject()
        defer { t.remove() }
        try t.write(
            "config.json",
            #"{"warnPaths": ["/opt", "relative/x", 5, "~/secret"], "allowPaths": "no"}"#)
        let policy = PathPolicy.load(from: t.url.appendingPathComponent("config.json"), home: t.real)
        #expect(policy.warn.contains("/opt"))
        #expect(policy.warn.contains { $0.hasSuffix("/secret") })
        #expect(!policy.warn.contains { $0.contains("relative") })
        #expect(policy.problems.count == 3)  // A relative path, a number, and the type of allowPaths
        #expect(!policy.warn.contains("/usr"))  // Writing it replaces the default
        #expect(policy.allow.contains { $0.hasSuffix("Mobile Documents") })  // invalid allowPaths: default stays
    }

    @Test func missingConfigUsesDefaults() throws {
        let t = try TempProject()
        defer { t.remove() }
        let policy = PathPolicy.load(from: t.url.appendingPathComponent("none.json"), home: t.real)
        #expect(policy.warn.contains("/usr") && policy.problems.isEmpty)
        let none = PathPolicy(home: t.real, warn: [])
        #expect(none.warn.isEmpty)
    }
}
