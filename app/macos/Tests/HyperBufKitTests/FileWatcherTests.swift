// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

/// Receives a notification and waits a fixed time. Notifications arrive on the main queue.
@MainActor
private final class Collector {
    var events: [(String, FileWatcher.State)] = []

    func wait(for path: String, _ state: FileWatcher.State, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if events.contains(where: { $0.0 == path && $0.1 == state }) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return events.contains(where: { $0.0 == path && $0.1 == state })
    }

    func count(_ path: String) -> Int { events.filter { $0.0 == path }.count }
}

@Suite(.serialized) @MainActor struct FileWatcherTests {
    private func makeWatcher(_ c: Collector) -> FileWatcher {
        FileWatcher(debounce: 0.03) { path, state in
            MainActor.assumeIsolated { c.events.append((path, state)) }
        }
    }

    @Test func reportsInPlaceModification() async throws {
        let t = try TempProject(files: ["a.md": "one"])
        defer { t.remove() }
        let path = t.real + "/a.md"
        let c = Collector()
        let watcher = makeWatcher(c)
        watcher.setPaths([path])
        try await Task.sleep(for: .milliseconds(100))
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("two".utf8))
        try handle.close()
        #expect(await c.wait(for: path, .changed))
        withExtendedLifetime(watcher) {}
    }

    @Test func reportsAtomicReplacementRepeatedly() async throws {
        // Detects, twice in a row, the save method that writes a temporary file and replaces (the inode changes) (checks re-attachment)
        let t = try TempProject(files: ["a.md": "one"])
        defer { t.remove() }
        let path = t.real + "/a.md"
        let c = Collector()
        let watcher = makeWatcher(c)
        watcher.setPaths([path])
        try await Task.sleep(for: .milliseconds(100))
        try t.write("a.md", "two")  // atomically: true -> replace
        #expect(await c.wait(for: path, .changed))
        let first = c.count(path)
        try await Task.sleep(for: .milliseconds(150))
        try t.write("a.md", "three!")
        let deadline = ContinuousClock.now + .seconds(5)
        while c.count(path) == first && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(c.count(path) > first)
        withExtendedLifetime(watcher) {}
    }

    @Test func reportsDeletionAndRecreation() async throws {
        let t = try TempProject(files: ["a.md": "one"])
        defer { t.remove() }
        let path = t.real + "/a.md"
        let c = Collector()
        let watcher = makeWatcher(c)
        watcher.setPaths([path])
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(atPath: path)
        #expect(await c.wait(for: path, .deleted))
        c.events.removeAll()
        try t.write("a.md", "back")
        #expect(await c.wait(for: path, .changed))  // Recreation is changed
        withExtendedLifetime(watcher) {}
    }

    @Test func onlyWatchedFilesAreReportedAndSiblingsAreIgnored() async throws {
        let t = try TempProject(files: ["a.md": "one", "b.md": "one"])
        defer { t.remove() }
        let a = t.real + "/a.md"
        let b = t.real + "/b.md"
        let c = Collector()
        let watcher = makeWatcher(c)
        watcher.setPaths([a])
        try await Task.sleep(for: .milliseconds(100))
        try t.write("b.md", "two")
        try t.write("sub/new.md", "x")
        try t.write("a.md", "two")
        #expect(await c.wait(for: a, .changed))
        try await Task.sleep(for: .milliseconds(200))
        #expect(c.count(b) == 0)
        #expect(!c.events.contains { $0.0.contains("new.md") })
        withExtendedLifetime(watcher) {}
    }

    @Test func removedPathsStopBeingReported() async throws {
        let t = try TempProject(files: ["a.md": "one", "b.md": "one"])
        defer { t.remove() }
        let a = t.real + "/a.md"
        let b = t.real + "/b.md"
        let c = Collector()
        let watcher = makeWatcher(c)
        watcher.setPaths([a, b])
        watcher.setPaths([b])
        try await Task.sleep(for: .milliseconds(100))
        try t.write("a.md", "two")
        try t.write("b.md", "two")
        #expect(await c.wait(for: b, .changed))
        try await Task.sleep(for: .milliseconds(200))
        #expect(c.count(a) == 0)
        withExtendedLifetime(watcher) {}
    }
}
