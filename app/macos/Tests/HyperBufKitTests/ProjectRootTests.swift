// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct ProjectRootTests {
    private func canon(_ t: TempProject, _ sub: String = "") -> String {
        let base = PathUtil.canonicalPath(t.url.path) ?? t.url.path
        return sub.isEmpty ? base : base + "/" + sub
    }

    private func mkdir(_ t: TempProject, _ sub: String) throws {
        try FileManager.default.createDirectory(
            at: t.url.appendingPathComponent(sub), withIntermediateDirectories: true)
    }

    @Test func findsTheNearestAncestorWithAMarker() throws {
        let t = try TempProject()
        defer { t.remove() }
        try mkdir(t, "repo/.git")
        try mkdir(t, "repo/docs/deep")
        let home = canon(t, "home")
        #expect(ProjectRoot.find(from: canon(t, "repo/docs/deep"), home: home) == canon(t, "repo"))
        #expect(ProjectRoot.find(from: canon(t, "repo"), home: home) == canon(t, "repo"))
    }

    @Test func gitFileCountsAsAMarker() throws {
        let t = try TempProject()
        defer { t.remove() }
        try mkdir(t, "wt/sub")
        try t.write("wt/.git", "gitdir: /elsewhere")
        #expect(ProjectRoot.find(from: canon(t, "wt/sub"), home: canon(t, "home")) == canon(t, "wt"))
    }

    @Test func fallsBackToTheDirectoryItself() throws {
        let t = try TempProject()
        defer { t.remove() }
        try mkdir(t, "Downloads/notes")
        let dir = canon(t, "Downloads/notes")
        #expect(ProjectRoot.find(from: dir, home: canon(t, "home")) == dir)
    }

    @Test func nearestMarkerWinsOverOuterOne() throws {
        let t = try TempProject()
        defer { t.remove() }
        try mkdir(t, "outer/.git")
        try mkdir(t, "outer/inner/.hg")
        #expect(ProjectRoot.find(from: canon(t, "outer/inner"), home: canon(t, "home")) == canon(t, "outer/inner"))
    }

    @Test func doesNotAscendToOrPastTheHome() throws {
        let t = try TempProject()
        defer { t.remove() }
        // ホスト自体が dotfiles のリポジトリでも、ルートにしない
        try mkdir(t, "home/.git")
        try mkdir(t, "home/notes")
        let dir = canon(t, "home/notes")
        #expect(ProjectRoot.find(from: dir, home: canon(t, "home")) == dir)
        #expect(ProjectRoot.find(from: canon(t, "home"), home: canon(t, "home")) == canon(t, "home"))
    }

    @Test func ignoredDirectoriesAreSkipped() throws {
        let t = try TempProject()
        defer { t.remove() }
        try mkdir(t, "wrapper/.git")
        try mkdir(t, "wrapper/sub/docs")
        let dir = canon(t, "wrapper/sub/docs")
        #expect(ProjectRoot.find(from: dir, home: canon(t, "home"), ignore: [canon(t, "wrapper")]) == dir)
        // 無視するのは完全一致だけ。内側の目印は有効
        try mkdir(t, "wrapper/sub/.git")
        #expect(
            ProjectRoot.find(from: dir, home: canon(t, "home"), ignore: [canon(t, "wrapper")])
                == canon(t, "wrapper/sub"))
    }
}
