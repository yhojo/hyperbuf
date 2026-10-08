import CryptoKit
import Foundation
import Testing

@testable import HyperBufKit

@Suite struct FileFingerprintTests {
    @Test func sha256IsHexOfTheBytes() {
        // "abc" の SHA-256(標準のテストベクトル)
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
            project: Project(root: t.url), trusted: TrustedRoots(url: state.url.appendingPathComponent("t.json")))
        let path = try access.absolutePath("a.md")
        #expect(access.fingerprints.get(path) == nil)

        _ = try access.readMarkdown("a.md")
        let first = try #require(access.fingerprints.get(path))
        #expect(first.sha256 == FileFingerprint.sha256Hex(Data("one\n".utf8)))
        #expect(first.size == 4)

        // ファイルが変わっても、読み直すまでは、「ビューアが描画した版」の識別情報のまま
        try t.write("a.md", "two!\n")
        #expect(access.fingerprints.get(path) == first)
        _ = try access.readMarkdown("a.md")
        let second = try #require(access.fingerprints.get(path))
        #expect(second.sha256 == FileFingerprint.sha256Hex(Data("two!\n".utf8)))
        #expect(second.sha256 != first.sha256)
    }

    @Test func hashesTheRawBytesEvenForInvalidUtf8() throws {
        let t = try TempProject()
        let state = try TempProject()
        defer { removeAll(t, state) }
        let bytes = Data([0x23, 0x20, 0xFF, 0xFE, 0x0A])  // 不正な UTF-8 を含む
        try bytes.write(to: t.url.appendingPathComponent("raw.md"))
        let access = FileAccess(
            project: Project(root: t.url), trusted: TrustedRoots(url: state.url.appendingPathComponent("t.json")))
        _ = try access.readMarkdown("raw.md")
        let path = try access.absolutePath("raw.md")
        // 文字列に直す前の、ディスク上のバイト列のハッシュ(エディタが、ディスクのファイルと比べるもの)
        #expect(access.fingerprints.get(path)?.sha256 == FileFingerprint.sha256Hex(bytes))
    }
}
