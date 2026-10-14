// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct UserSettingsTests {
    private func load(_ t: TempProject, _ json: String) throws -> UserSettings {
        try t.write("config.json", json)
        return UserSettings.load(from: t.url.appendingPathComponent("config.json"))
    }

    @Test func defaultsWhenMissingOrEmpty() throws {
        let t = try TempProject()
        defer { t.remove() }
        let missing = UserSettings.load(from: t.url.appendingPathComponent("none.json"))
        #expect(missing.restoreSession && missing.mathUnescapeUnderscore && !missing.followUpdates)
        #expect(missing.trustedUrls.isEmpty && missing.problems.isEmpty)
        #expect(try load(t, "{}") == UserSettings())
    }

    @Test func appearanceDefaultsToSystemAndAcceptsThreeValues() throws {
        let t = try TempProject()
        defer { t.remove() }
        #expect(try load(t, "{}").appearance == .system)
        #expect(try load(t, #"{"appearance": "dark"}"#).appearance == .dark)
        #expect(try load(t, #"{"appearance": "light"}"#).appearance == .light)
        #expect(try load(t, #"{"appearance": "system"}"#).appearance == .system)
    }

    @Test func invalidAppearanceKeepsSystemAndIsReported() throws {
        let t = try TempProject()
        defer { t.remove() }
        for bad in [#""blue""#, "true", "1", "null"] {
            let s = try load(t, #"{"appearance": \#(bad)}"#)
            #expect(s.appearance == .system)
            #expect(s.problems.count == 1 && s.problems[0].contains("appearance"))
        }
    }

    @Test func readsFlagsAndUrls() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = try load(
            t,
            #"{"restoreSession": false, "mathUnescapeUnderscore": false, "followUpdates": true, "trustedUrls": ["https://github.com/*", "http://localhost:*"]}"#
        )
        #expect(!s.restoreSession && !s.mathUnescapeUnderscore && s.followUpdates)
        #expect(s.trustedUrls == ["https://github.com/*", "http://localhost:*"])
        #expect(s.problems.isEmpty)
    }

    @Test func invalidValuesKeepDefaultsAndAreReported() throws {
        let t = try TempProject()
        defer { t.remove() }
        let s = try load(
            t,
            #"{"followUpdates": "yes", "mathUnescapeUnderscore": 1, "trustedUrls": ["ftp://x/*", "javascript:alert(1)", "", 5, "https://ok.example/*"]}"#
        )
        #expect(!s.followUpdates && s.mathUnescapeUnderscore)  // 型が違えば(文字列・数値)、既定のまま
        #expect(s.trustedUrls == ["https://ok.example/*"])  // http / https のパターンだけ
        #expect(s.problems.count == 2 + 4)
        let bad = try load(t, #"{"trustedUrls": "https://x/*"}"#)
        #expect(bad.trustedUrls.isEmpty && bad.problems.count == 1)
    }

    @Test func brokenFileGivesDefaults() throws {
        let t = try TempProject()
        defer { t.remove() }
        #expect(try load(t, "{broken") == UserSettings())
    }
}
