// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct SessionStoreTests {
    private func store(_ t: TempProject) -> SessionStore {
        SessionStore(directory: t.url.appendingPathComponent("state"))
    }

    private func frame(_ slot: Int) -> [String: Any] {
        [
            "slot": slot, "rect": ["x": 10, "y": 20, "width": 900, "height": 600],
            "snapshot": ["version": 1, "selected": 1, "winSeq": 1, "mru": ["/a.md"]],
        ]
    }

    @Test func savesAndLoadsTheFrameList() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        #expect(s.load() == nil)
        #expect(s.save(["version": 2, "active": 2, "frames": [frame(1), frame(2)]]))
        let loaded = s.load()
        #expect(loaded?["active"] as? Int == 2)
        #expect((loaded?["frames"] as? [[String: Any]])?.compactMap { $0["slot"] as? Int } == [1, 2])
    }

    @Test func storeIsPrivate() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        #expect(s.save(["version": 2, "active": 1, "frames": [frame(1)]]))
        let dirMode = try FileManager.default.attributesOfItem(atPath: s.directory.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: s.fileURL.path)[.posixPermissions] as? Int
        #expect(dirMode == 0o700)
        #expect(fileMode == 0o600)
    }

    @Test func overwritesAndKeepsNoTemporaryFiles() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        #expect(s.save(["version": 2, "active": 1, "frames": [frame(1)]]))
        #expect(s.save(["version": 2, "active": 3, "frames": [frame(3)]]))
        #expect(s.load()?["active"] as? Int == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.directory.path).count == 1)
    }

    @Test func refusesOversizedAndInvalid() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        let big: [String: Any] = [
            "version": 2,
            "frames": [["slot": 1, "snapshot": ["x": String(repeating: "x", count: SessionStore.maxBytes)]]],
        ]
        #expect(!s.save(big))
        #expect(!s.save(["bad": Date()]))
        #expect(s.load() == nil)
    }

    @Test func dropsFramesWithInvalidOrDuplicateSlots() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        #expect(s.save(["version": 2, "active": 1, "frames": [frame(1), frame(1), frame(0), frame(10), frame(4)]]))
        let slots = (s.load()?["frames"] as? [[String: Any]])?.compactMap { $0["slot"] as? Int }
        #expect(slots == [1, 4])
    }

    @Test func ignoresBrokenWrongVersionAndOversizedFiles() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = store(t)
        #expect(s.save(["version": 2, "active": 1, "frames": [frame(1)]]))
        try "{broken".write(to: s.fileURL, atomically: true, encoding: .utf8)
        #expect(s.load() == nil)
        try #"{"version": 1, "frames": []}"#.write(to: s.fileURL, atomically: true, encoding: .utf8)
        #expect(s.load() == nil)
        try String(repeating: " ", count: SessionStore.maxBytes + 1).write(
            to: s.fileURL, atomically: true, encoding: .utf8)
        #expect(s.load() == nil)
    }

    @Test func restoreSettingDefaultsToOn() throws {
        let t = try TempProject()
        defer { t.remove() }
        let url = t.url.appendingPathComponent("config.json")
        #expect(SessionSettings.restoreEnabled(from: url))  // No file
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        #expect(SessionSettings.restoreEnabled(from: url))
        try #"{"restoreSession": false}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(!SessionSettings.restoreEnabled(from: url))
        try #"{"restoreSession": "no"}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(SessionSettings.restoreEnabled(from: url))  // If not a Boolean, the default stays
    }
}
