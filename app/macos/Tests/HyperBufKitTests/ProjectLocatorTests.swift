import Foundation
import Testing

@testable import HyperBufKit

@Suite struct ProjectLocatorTests {
    @Test func prefersNearestGitAncestor() throws {
        let t = try TempProject(files: ["repo/.git/HEAD": "", "repo/docs/deep/a.md": ""])
        defer { t.remove() }
        let file = t.url.appendingPathComponent("repo/docs/deep/a.md").path
        let root = ProjectLocator.root(for: file)
        #expect(root == Project.canonicalPath(t.url.appendingPathComponent("repo").path))
    }

    @Test func fallsBackToTheFilesDirectory() throws {
        // 一時ディレクトリの祖先に .git がないことが前提(あれば、その祖先になる)
        let t = try TempProject(files: ["docs/a.md": ""])
        defer { t.remove() }
        let file = t.url.appendingPathComponent("docs/a.md").path
        let root = ProjectLocator.root(for: file)
        let expected = Project.canonicalPath(t.url.appendingPathComponent("docs").path)
        #expect(root == expected)
    }

    @Test func nearestGitWinsOverOuterGit() throws {
        let t = try TempProject(files: [".git/HEAD": "", "outer/inner/.git/HEAD": "", "outer/inner/x/a.md": ""])
        defer { t.remove() }
        let file = t.url.appendingPathComponent("outer/inner/x/a.md").path
        #expect(
            ProjectLocator.root(for: file) == Project.canonicalPath(t.url.appendingPathComponent("outer/inner").path))
    }
}
