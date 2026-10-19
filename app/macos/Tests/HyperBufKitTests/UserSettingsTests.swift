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

    @Test func alphaDefaultsToOpaqueAndReadsTwoPercentages() throws {
        let t = try TempProject()
        defer { t.remove() }
        #expect(try load(t, "{}").alpha == .opaque)
        let s = try load(t, #"{"alpha": [80, 65]}"#)
        #expect(s.alpha == WindowAlpha(active: 80, inactive: 65) && s.problems.isEmpty)
        #expect(try load(t, #"{"alpha": [100, 10]}"#).alpha == WindowAlpha(active: 100, inactive: 10))
    }

    @Test func invalidAlphaKeepsOpaqueAndIsReported() throws {
        let t = try TempProject()
        defer { t.remove() }
        for bad in [
            "80", "[80]", "[80, 65, 50]", "[0, 65]", "[80, 101]", "[80.5, 65]", #"["80", 65]"#, "[true, 65]", "null",
        ] {
            let s = try load(t, #"{"alpha": \#(bad)}"#)
            #expect(s.alpha == .opaque, "\(bad)")
            #expect(s.problems.count == 1 && s.problems[0].contains("alpha"), "\(bad)")
        }
    }

    @Test func windowAlphaValueFollowsKeyStateAndAccessibility() {
        let a = WindowAlpha(active: 80, inactive: 65)
        #expect(a.value(isKey: true, reduceTransparency: false) == 0.8)
        #expect(a.value(isKey: false, reduceTransparency: false) == 0.65)
        #expect(a.value(isKey: true, reduceTransparency: true) == 1)
        #expect(a.value(isKey: false, reduceTransparency: true) == 1)
        #expect(WindowAlpha.opaque.value(isKey: false, reduceTransparency: false) == 1)
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
        #expect(!s.followUpdates && s.mathUnescapeUnderscore)  // Wrong types (string, number) stay at their defaults
        #expect(s.trustedUrls == ["https://ok.example/*"])  // Only http / https patterns
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

extension UserSettingsTests {
    @Test func projectIgnorePathsAcceptsAbsoluteAndTildePaths() throws {
        let t = try TempProject()
        defer { t.remove() }
        let ok = try load(t, #"{"projectIgnorePaths": ["~/.git-home", "/Users/x/wrapper"]}"#)
        #expect(ok.projectIgnorePaths == ["~/.git-home", "/Users/x/wrapper"] && ok.problems.isEmpty)
        let bad = try load(t, #"{"projectIgnorePaths": ["relative/dir", 3, ""]}"#)
        #expect(bad.projectIgnorePaths.isEmpty && bad.problems.count == 3)
        let wrongType = try load(t, #"{"projectIgnorePaths": "~/x"}"#)
        #expect(wrongType.projectIgnorePaths.isEmpty && wrongType.problems.count == 1)
        #expect(try load(t, "{}").projectIgnorePaths.isEmpty)
    }
}
