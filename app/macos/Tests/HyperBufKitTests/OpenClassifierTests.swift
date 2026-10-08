import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufKit

@Suite struct OpenClassifierTests {
    private func validated(_ path: String) -> ValidatedOpen {
        guard case .success(let v) = OpenRequestValidator.validate(path: path, line: nil, anchor: nil, version: nil)
        else {
            fatalError("検証に失敗: \(path)")
        }
        return v
    }

    @Test func classifiesInsideTrustedOutsideAndMissing() throws {
        let project = try TempProject(files: ["a.md": "", "sub/b.md": ""])
        let other = try TempProject(files: ["repo/.git/HEAD": "", "repo/docs/c.md": "", "free/d.md": ""])
        let state = try TempProject()
        defer { removeAll(project, other, state) }
        let trusted = TrustedRoots(url: state.url.appendingPathComponent("t.json"))
        let p = Project(root: project.url)

        let inside = OpenClassifier.classify(validated(project.url.path + "/sub/b.md"), project: p, trusted: trusted)
        #expect(try inside.get() == .inside(relative: "sub/b.md"))

        let cPath = other.url.path + "/repo/docs/c.md"
        guard
            case .outside(let absolute, let root) = try OpenClassifier.classify(
                validated(cPath), project: p, trusted: trusted
            ).get()
        else {
            Issue.record("範囲外のはず")
            return
        }
        #expect(absolute == Project.canonicalPath(cPath))
        #expect(root == Project.canonicalPath(other.url.path + "/repo"))  // .git を含む祖先を、信頼するルートとして提案する

        trusted.add(root)
        let after = OpenClassifier.classify(validated(cPath), project: p, trusted: trusted)
        #expect(try after.get() == .trusted(absolute: Project.canonicalPath(cPath)!))

        let missing = OpenClassifier.classify(validated(project.url.path + "/nope.md"), project: p, trusted: trusted)
        guard case .failure(let error) = missing else {
            Issue.record("失敗するはず")
            return
        }
        #expect(error.code == ErrorCode.notFound.rawValue)
    }

    @Test func symlinkIntoTheProjectFromOutsideIsJudgedByItsTarget() throws {
        let project = try TempProject(files: ["a.md": ""])
        let outside = try TempProject(files: ["secret.md": ""])
        defer { removeAll(project, outside) }
        try FileManager.default.createSymbolicLink(
            at: project.url.appendingPathComponent("link.md"),
            withDestinationURL: outside.url.appendingPathComponent("secret.md"))
        let state = try TempProject()
        defer { state.remove() }
        let result = OpenClassifier.classify(
            validated(project.url.path + "/link.md"), project: Project(root: project.url),
            trusted: TrustedRoots(url: state.url.appendingPathComponent("t.json")))
        // プロジェクト内にあるリンクでも、実体が範囲外なら、範囲外(確認が要る)
        guard case .outside = try result.get() else {
            Issue.record("範囲外のはず")
            return
        }
    }
}
