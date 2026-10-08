import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufKit

@Suite struct LocationBuilderTests {
    private func web(path: String, precision: LocationPayload.Precision = .exact) -> WebLocation {
        let json = """
            {"path": \(String(reflecting: path)), "range": {"start": {"line": 1, "column": 3}, "end": {"line": 1, "column": 6}},
             "precision": "\(precision.rawValue)", "expect": "abc", "expectTruncated": false,
             "context": {"before": "x ", "after": " y"}, "selection": "abc", "version": 4}
            """
        // swiftlint を使わず、JSON のエスケープは、JSONSerialization に任せる
        let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return (try? JSONDecoder().decode(WebLocation.self, from: data))!
    }

    private func access(_ t: TempProject, _ state: TempProject) -> FileAccess {
        FileAccess(
            project: Project(root: t.url), trusted: TrustedRoots(url: state.url.appendingPathComponent("t.json")))
    }

    @Test func buildsAnAbsolutePathAndFileFingerprint() throws {
        let t = try TempProject(files: ["docs/a.md": "x abc y\n"])
        let state = try TempProject()
        defer { removeAll(t, state) }
        let access = access(t, state)
        _ = try access.readMarkdown("docs/a.md")  // ビューアが読んだ版

        let now = Date(timeIntervalSince1970: 1000)
        let payload = try LocationBuilder.build(web(path: "docs/a.md"), access: access, now: now).get()
        #expect(payload.path == Project.canonicalPath(t.url.path + "/docs/a.md"))
        #expect(payload.file.sha256 == FileFingerprint.sha256Hex(Data("x abc y\n".utf8)))
        #expect(payload.file.size == 8)
        #expect(payload.viewer.version == 4 && payload.viewer.selection == "abc")
        #expect(payload.markedAt == 1_000_000)
        #expect(payload.precision == .exact)
        #expect(payload.range.start == .init(line: 1, column: 3))
        #expect(payload.v == 1)
    }

    @Test func rejectsFilesOutsideTheProjectAndTrustedRoots() throws {
        let t = try TempProject(files: ["a.md": "x"])
        let outside = try TempProject(files: ["secret.md": "s"])
        let state = try TempProject()
        defer { removeAll(t, outside, state) }
        let access = access(t, state)
        let result = LocationBuilder.build(web(path: outside.url.path + "/secret.md"), access: access)
        guard case .failure(let error) = result else {
            Issue.record("拒否されるはず")
            return
        }
        #expect(error.code == ErrorCode.outsideProject.rawValue)
        #expect(throws: ProjectError.outside) { try access.absolutePath("../x.md") }
    }

    @Test func allowsTrustedRootsByAbsolutePath() throws {
        let t = try TempProject(files: ["a.md": "x"])
        let outside = try TempProject(files: ["n/b.md": "bb"])
        let state = try TempProject()
        defer { removeAll(t, outside, state) }
        let access = access(t, state)
        access.trusted.add(outside.url.appendingPathComponent("n").path)
        let file = outside.url.path + "/n/b.md"
        _ = try access.readMarkdown(file)
        let payload = try LocationBuilder.build(web(path: file), access: access).get()
        #expect(payload.path == Project.canonicalPath(file))
    }

    @Test func refusesWhenThereIsNoRecordOfTheRenderedVersion() throws {
        let t = try TempProject(files: ["a.md": "x"])
        let state = try TempProject()
        defer { removeAll(t, state) }
        // ビューアが、まだ読んでいない(描画した版が分からない)ファイルの位置は、渡さない
        let result = LocationBuilder.build(web(path: "a.md"), access: access(t, state))
        guard case .failure(let error) = result else {
            Issue.record("拒否されるはず")
            return
        }
        #expect(error.code == ErrorCode.stale.rawValue)
    }
}
