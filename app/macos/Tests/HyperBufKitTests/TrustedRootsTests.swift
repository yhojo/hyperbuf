import Foundation
import Testing

@testable import HyperBufKit

@Suite struct TrustedRootsTests {
    private func storeURL(_ t: TempProject) -> URL { t.url.appendingPathComponent("state/trusted-roots.json") }

    @Test func persistsAcrossInstances() throws {
        let t = try TempProject()
        let area = try TempProject(files: ["x/a.md": "a"])
        defer {
            t.remove()
            area.remove()
        }
        let first = TrustedRoots(url: storeURL(t))
        #expect(first.all.isEmpty)
        #expect(first.add(area.url.path))
        let second = TrustedRoots(url: storeURL(t))
        #expect(second.all.count == 1)
        #expect(second.contains(area.url.appendingPathComponent("x/a.md").path))
    }

    @Test func storeIsPrivate() throws {
        let t = try TempProject()
        let area = try TempProject()
        defer {
            t.remove()
            area.remove()
        }
        let store = TrustedRoots(url: storeURL(t))
        store.add(area.url.path)
        func mode(_ path: String) -> Int {
            ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int) ?? -1
        }
        #expect(mode(storeURL(t).path) == 0o600)
        #expect(mode(storeURL(t).deletingLastPathComponent().path) == 0o700)
    }

    @Test func containsOnlyInsideTheRoot() throws {
        let t = try TempProject()
        let area = try TempProject(files: ["a.md": ""])
        let other = try TempProject(files: ["b.md": ""])
        defer {
            t.remove()
            area.remove()
            other.remove()
        }
        let store = TrustedRoots(url: storeURL(t))
        store.add(area.url.path)
        #expect(store.contains(area.url.appendingPathComponent("a.md").path))
        #expect(!store.contains(other.url.appendingPathComponent("b.md").path))
        // 接頭辞が同じだけの、別のディレクトリは含まれない
        let sibling = area.url.path + "-evil"
        try FileManager.default.createDirectory(atPath: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: sibling) }
        #expect(!store.contains(sibling))
    }

    @Test func symlinkOutOfTheRootIsNotTrusted() throws {
        let t = try TempProject()
        let area = try TempProject()
        let secret = try TempProject(files: ["s.md": ""])
        defer {
            t.remove()
            area.remove()
            secret.remove()
        }
        try FileManager.default.createSymbolicLink(
            at: area.url.appendingPathComponent("link.md"),
            withDestinationURL: secret.url.appendingPathComponent("s.md"))
        let store = TrustedRoots(url: storeURL(t))
        store.add(area.url.path)
        #expect(!store.contains(area.url.appendingPathComponent("link.md").path))
    }

    @Test func doesNotAddMissingDirectoriesAndIgnoresCorruptFiles() throws {
        let t = try TempProject(files: ["state/trusted-roots.json": "{broken"])
        defer { t.remove() }
        let store = TrustedRoots(url: storeURL(t))
        #expect(store.all.isEmpty)
        #expect(!store.add("/no/such/dir/anywhere"))
    }
}
