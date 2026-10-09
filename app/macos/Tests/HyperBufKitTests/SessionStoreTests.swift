import Foundation
import Testing

@testable import HyperBufKit

@Suite struct SessionStoreTests {
    private func store(_ t: TempProject) -> SessionStore {
        SessionStore(directory: t.url.appendingPathComponent("sessions"))
    }

    private let sample: [String: Any] = [
        "version": 1, "selected": 1, "winSeq": 1, "mru": ["a.md"],
        "root": [
            "type": "leaf", "id": 1, "index": 0, "history": [["path": "a.md", "anchor": NSNull(), "scroll": 12.5]],
        ],
    ]

    @Test func savesAndLoadsPerProject() throws {
        let t = try TempProject()
        let other = try TempProject()
        defer {
            t.remove()
            other.remove()
        }
        let s = store(t)
        #expect(s.load(for: Project(root: t.url)) == nil)
        #expect(s.save(sample, for: Project(root: t.url)))
        let loaded = s.load(for: Project(root: t.url)) as? [String: Any]
        #expect(loaded?["winSeq"] as? Int == 1)
        #expect(s.load(for: Project(root: other.url)) == nil)  // 別のプロジェクトのものは読まない
    }

    @Test func storeIsPrivate() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        let project = Project(root: t.url)
        #expect(s.save(sample, for: project))
        let dirMode = try FileManager.default.attributesOfItem(atPath: s.directory.path)[.posixPermissions] as? Int
        let fileMode =
            try FileManager.default.attributesOfItem(atPath: s.fileURL(for: project).path)[.posixPermissions] as? Int
        #expect(dirMode == 0o700)
        #expect(fileMode == 0o600)
    }

    @Test func overwritesAndKeepsNoTemporaryFiles() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        let project = Project(root: t.url)
        #expect(s.save(["a": 1], for: project))
        #expect(s.save(["a": 2], for: project))
        #expect((s.load(for: project) as? [String: Any])?["a"] as? Int == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.directory.path).count == 1)
    }

    @Test func refusesOversizedAndInvalid() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        let project = Project(root: t.url)
        #expect(!s.save(["big": String(repeating: "x", count: SessionStore.maxBytes)], for: project))
        #expect(!s.save(["bad": Date()], for: project))
        #expect(s.load(for: project) == nil)
    }

    @Test func ignoresBrokenAndOversizedFiles() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        let project = Project(root: t.url)
        #expect(s.save(sample, for: project))
        try "{broken".write(to: s.fileURL(for: project), atomically: true, encoding: .utf8)
        #expect(s.load(for: project) == nil)
        try String(repeating: " ", count: SessionStore.maxBytes + 1).write(
            to: s.fileURL(for: project), atomically: true, encoding: .utf8)
        #expect(s.load(for: project) == nil)
    }

    @Test func restoreSettingDefaultsToOn() throws {
        let t = try TempProject()
        defer { t.remove() }
        let url = t.url.appendingPathComponent("config.json")
        #expect(SessionSettings.restoreEnabled(from: url))  // ファイルなし
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        #expect(SessionSettings.restoreEnabled(from: url))
        try #"{"restoreSession": false}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(!SessionSettings.restoreEnabled(from: url))
        try #"{"restoreSession": "no"}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(SessionSettings.restoreEnabled(from: url))  // 真偽値でなければ、既定のまま
    }
}
