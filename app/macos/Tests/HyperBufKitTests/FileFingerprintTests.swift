// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import CryptoKit
import Foundation
import Testing

@testable import HyperBufKit

@Suite struct FileFingerprintTests {
    @Test func sha256IsHexOfTheBytes() {
        // SHA-256 of "abc" (the standard test vector)
        #expect(
            FileFingerprint.sha256Hex(Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(FileFingerprint.sha256Hex(Data()).count == 64)
    }

    @Test func recordsTheBytesThatWereServedAndUpdatesOnRead() throws {
        let t = try TempProject(files: ["a.md": "one\n"])
        let state = try TempProject()
        defer { removeAll(t, state) }
        let access = FileAccess(
            policy: PathPolicy(home: t.real, warn: [], allow: []),
            remembered: RememberedPaths(url: state.url.appendingPathComponent("t.json")))
        let file = t.url.path + "/a.md"
        let path = try access.canonical(file)
        #expect(access.fingerprints.get(path) == nil)

        _ = try access.readMarkdown(file)
        let first = try #require(access.fingerprints.get(path))
        #expect(first.sha256 == FileFingerprint.sha256Hex(Data("one\n".utf8)))
        #expect(first.size == 4)

        // Even if the file changes, until it is re-read the identity stays that of "the version the viewer rendered"
        try t.write("a.md", "two!\n")
        #expect(access.fingerprints.get(path) == first)
        _ = try access.readMarkdown(file)
        let second = try #require(access.fingerprints.get(path))
        #expect(second.sha256 == FileFingerprint.sha256Hex(Data("two!\n".utf8)))
        #expect(second.sha256 != first.sha256)
    }

    @Test func hashesTheRawBytesEvenForInvalidUtf8() throws {
        let t = try TempProject()
        let state = try TempProject()
        defer { removeAll(t, state) }
        let bytes = Data([0x23, 0x20, 0xFF, 0xFE, 0x0A])  // Contains invalid UTF-8
        try bytes.write(to: t.url.appendingPathComponent("raw.md"))
        let access = FileAccess(
            policy: PathPolicy(home: t.real, warn: [], allow: []),
            remembered: RememberedPaths(url: state.url.appendingPathComponent("t.json")))
        let file = t.url.path + "/raw.md"
        _ = try access.readMarkdown(file)
        let path = try access.canonical(file)
        // The hash of the on-disk bytes before conversion to a string (what the editor compares with the file on disk)
        #expect(access.fingerprints.get(path)?.sha256 == FileFingerprint.sha256Hex(bytes))
    }
}
