import Foundation
import Testing

@testable import HyperBufKit

@Suite struct FileAccessTests {
    private func setup() throws -> (project: TempProject, outside: TempProject, state: TempProject, access: FileAccess)
    {
        let project = try TempProject(files: ["a.md": "inside", "img/p.png": "png"])
        let outside = try TempProject(files: ["notes/o.md": "outside", "notes/img/q.svg": "<svg/>", "x.txt": ""])
        let state = try TempProject()
        let trusted = TrustedRoots(url: state.url.appendingPathComponent("t.json"))
        return (project, outside, state, FileAccess(project: Project(root: project.url), trusted: trusted))
    }

    @Test func relativePathsAreProjectOnly() throws {
        let s = try setup()
        defer { removeAll(s.project, s.outside, s.state) }
        #expect(try s.access.readMarkdown("a.md") == "inside")
        #expect(throws: ProjectError.outside) { try s.access.readMarkdown("../x.md") }
    }

    @Test func absolutePathsRequireATrustedRoot() throws {
        let s = try setup()
        defer { removeAll(s.project, s.outside, s.state) }
        let file = s.outside.url.appendingPathComponent("notes/o.md").path
        #expect(throws: ProjectError.outside) { try s.access.readMarkdown(file) }
        s.access.trusted.add(s.outside.url.appendingPathComponent("notes").path)
        #expect(try s.access.readMarkdown(file) == "outside")
        // 信頼するルートの外は、引き続き読めない
        let other = s.outside.url.appendingPathComponent("x.txt").path
        #expect(throws: ProjectError.notMarkdown) { try s.access.readMarkdown(other) }
    }

    @Test func absolutePathsWithDotDotAreRejected() throws {
        let s = try setup()
        defer { removeAll(s.project, s.outside, s.state) }
        s.access.trusted.add(s.outside.url.path)
        let sneaky = s.outside.url.path + "/notes/../notes/o.md"
        #expect(throws: ProjectError.outside) { try s.access.readMarkdown(sneaky) }
    }

    @Test func imagesFollowTheSameRules() throws {
        let s = try setup()
        defer { removeAll(s.project, s.outside, s.state) }
        let image = s.outside.url.appendingPathComponent("notes/img/q.svg").path
        #expect(throws: ProjectError.outside) { try s.access.readResource(image) }
        s.access.trusted.add(s.outside.url.path)
        #expect(try s.access.readResource(image).mime == "image/svg+xml")
        #expect(try s.access.readResource("img/p.png").mime == "image/png")
        #expect(throws: ProjectError.unsupportedResource) {
            try s.access.readResource(s.outside.url.path + "/notes/o.md")
        }
    }
}
