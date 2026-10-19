// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

extension Result where Success == Void {
    /// nil on success, the value on failure (`Void` is not Equatable, so results cannot be compared with `==` directly).
    fileprivate var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@Suite struct EditorCommandTests {
    private func config(_ t: TempProject, _ json: String) throws -> EditorConfig {
        try t.write("config.json", json)
        return EditorConfig.load(from: t.url.appendingPathComponent("config.json"))
    }

    @Test func loadsAValidCommandAndName() throws {
        let t = try TempProject()
        defer { t.remove() }
        let c = try config(
            t, #"{"editorName": "Emacs", "editorCommand": ["/usr/bin/true", "-n", "-e", "(hyperbuf-edit-here)"]}"#)
        #expect(c.command == ["/usr/bin/true", "-n", "-e", "(hyperbuf-edit-here)"])
        #expect(c.menuTitle == "Edit in Emacs")
    }

    @Test func withoutACommandItOnlyRecords() throws {
        let t = try TempProject()
        defer { t.remove() }
        #expect(EditorConfig.load(from: t.url.appendingPathComponent("none.json")).command == nil)
        #expect(try config(t, "{}").menuTitle == "Record Location for Editor")
        #expect(try config(t, "{broken").command == nil)
    }

    @Test func rejectsUnsafeCommands() throws {
        let t = try TempProject(files: ["plain.txt": "x"])
        defer { t.remove() }
        let bad: [String] = [
            #"{"editorCommand": ["emacsclient", "-n"]}"#,  // A relative path (PATH lookup is not allowed)
            #"{"editorCommand": ["/no/such/program"]}"#,  // Nonexistent
            #"{"editorCommand": ["\#(t.url.path)/plain.txt"]}"#,  // Not executable
            #"{"editorCommand": ["/usr/bin"]}"#,  // A directory
            #"{"editorCommand": []}"#,
            #"{"editorCommand": "/usr/bin/true"}"#,  // Not an array (a shell string is not accepted)
            #"{"editorCommand": ["/usr/bin/true", "a\u0000b"]}"#,
            #"{"editorCommand": ["/usr/bin/true", "\#(String(repeating: "x", count: 2000))"]}"#,
            #"{"editorCommand": ["/usr/bin/true", "1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16"]}"#,
        ]
        for json in bad {
            #expect(try config(t, json).command == nil, "\(json.prefix(60))")
        }
    }

    @Test func runsWithoutAShellAndReportsExitStatus() async throws {
        let ok = EditorConfig(command: ["/usr/bin/true"], name: "X")
        #expect(await EditorCommand.run(ok).failure == nil)
        let ng = EditorConfig(command: ["/usr/bin/false"], name: "X")
        #expect(await EditorCommand.run(ng).failure == .failed(1))
        #expect(await EditorCommand.run(EditorConfig(command: nil, name: "X")).failure == .notConfigured)
    }

    @Test func passesArgumentsLiterallyNoShellExpansion() async throws {
        let t = try TempProject()
        defer { t.remove() }
        // No shell is involved, so `$(...)` and `;` are passed as plain strings in the arguments
        let marker = t.url.appendingPathComponent("created-by-injection").path
        let script = t.url.appendingPathComponent("check.sh").path
        try "#!/bin/sh\n[ \"$1\" = '$(touch \(marker)); ls' ] || exit 7\n".write(
            toFile: script, atomically: true, encoding: .utf8)
        chmod(script, 0o755)
        let c = EditorConfig(command: [script, "$(touch \(marker)); ls"], name: "X")
        #expect(await EditorCommand.run(c).failure == nil)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func killsCommandsThatExceedTheTimeout() async throws {
        let c = EditorConfig(command: ["/bin/sleep", "30"], name: "X")
        let started = Date()
        #expect(await EditorCommand.run(c, timeout: 0.3).failure == .timedOut)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
