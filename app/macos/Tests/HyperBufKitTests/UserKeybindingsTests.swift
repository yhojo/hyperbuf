// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct UserKeybindingsTests {
    private func load(_ t: TempProject, _ json: String) throws -> [String: Any] {
        try t.write("config.json", json)
        return UserKeybindings.load(from: t.url.appendingPathComponent("config.json"))
    }

    @Test func loadsCommandsAndNullUnbinds() throws {
        let t = try TempProject()
        defer { t.remove() }
        let result = try load(t, #"{"keybindings": {"M-p": "back", "C-f": null, "C-x 2": "split-below"}}"#)
        #expect(result["M-p"] as? String == "back")
        #expect(result["C-f"] is NSNull)
        #expect(result["C-x 2"] as? String == "split-below")
        #expect(result.count == 3)
    }

    @Test func missingOrInvalidFilesGiveNothing() throws {
        let t = try TempProject()
        defer { t.remove() }
        #expect(UserKeybindings.load(from: t.url.appendingPathComponent("none.json")).isEmpty)
        #expect(try load(t, "{broken").isEmpty)
        #expect(try load(t, "{}").isEmpty)
        #expect(try load(t, #"{"keybindings": "M-p"}"#).isEmpty)  // Not an object
        #expect(try load(t, #"{"keybindings": ["a"]}"#).isEmpty)
    }

    @Test func dropsEntriesOfTheWrongTypeOrLength() throws {
        let t = try TempProject()
        defer { t.remove() }
        let long = String(repeating: "x", count: UserKeybindings.maxLength + 1)
        let result = try load(
            t,
            #"{"keybindings": {"a": 1, "b": true, "c": ["x"], "d": {"k": 1}, "ok": "back", "\#(long)": "back", "e": "\#(long)"}}"#
        )
        #expect(Set(result.keys) == ["ok"])
    }

    @Test func rejectsTooManyEntries() throws {
        let t = try TempProject()
        defer { t.remove() }
        let entries = (0...UserKeybindings.maxEntries).map { "\"k\($0)\": \"back\"" }.joined(separator: ",")
        #expect(try load(t, "{\"keybindings\": {\(entries)}}").isEmpty)
    }

    @Test func sharesTheFileWithTheEditorSettings() throws {
        let t = try TempProject()
        defer { t.remove() }
        try t.write(
            "config.json",
            #"{"editorName": "Emacs", "editorCommand": ["/usr/bin/true"], "keybindings": {"M-p": "back"}}"#)
        let url = t.url.appendingPathComponent("config.json")
        #expect(EditorConfig.load(from: url).command == ["/usr/bin/true"])
        #expect(UserKeybindings.load(from: url)["M-p"] as? String == "back")
    }
}
