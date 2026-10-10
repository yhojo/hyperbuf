// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct RememberedPathsTests {
    private func storeURL(_ t: TempProject) -> URL { t.url.appendingPathComponent("state/trusted-roots.json") }

    @Test func persistsAcrossInstances() throws {
        let t = try TempProject()
        let area = try TempProject(files: ["x/a.md": "a"])
        defer { removeAll(t, area) }
        let first = RememberedPaths(url: storeURL(t))
        #expect(first.all.isEmpty)
        #expect(first.add(area.url.path))
        let second = RememberedPaths(url: storeURL(t))
        #expect(second.all.count == 1)
        #expect(second.contains(area.url.appendingPathComponent("x/a.md").path))
    }

    @Test func rememberingAFileCoversOnlyThatFile() throws {
        let t = try TempProject()
        let area = try TempProject(files: ["a.md": "a", "b.md": "b"])
        defer { removeAll(t, area) }
        let store = RememberedPaths(url: storeURL(t))
        #expect(store.add(area.url.appendingPathComponent("a.md").path))
        #expect(store.contains(area.url.appendingPathComponent("a.md").path))
        #expect(!store.contains(area.url.appendingPathComponent("b.md").path))
    }

    @Test func removeForgets() throws {
        let t = try TempProject()
        let area = try TempProject(files: ["a.md": "a"])
        defer { removeAll(t, area) }
        let store = RememberedPaths(url: storeURL(t))
        store.add(area.url.path)
        #expect(store.remove(area.real))
        #expect(!store.contains(area.url.appendingPathComponent("a.md").path))
        #expect(RememberedPaths(url: storeURL(t)).all.isEmpty)
        #expect(!store.remove("/never/added"))
    }

    @Test func nonExistentPathsAreNotAdded() throws {
        let t = try TempProject()
        defer { t.remove() }
        let store = RememberedPaths(url: storeURL(t))
        #expect(!store.add("/no/such/dir"))
        #expect(store.all.isEmpty)
    }

    @Test func storeIsPrivate() throws {
        let t = try TempProject()
        let area = try TempProject()
        defer { removeAll(t, area) }
        let store = RememberedPaths(url: storeURL(t))
        store.add(area.url.path)
        let dirMode =
            try FileManager.default.attributesOfItem(atPath: storeURL(t).deletingLastPathComponent().path)[
                .posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: storeURL(t).path)[.posixPermissions] as? Int
        #expect(dirMode == 0o700)
        #expect(fileMode == 0o600)
    }
}
