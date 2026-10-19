// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

/// docs/user/configuration.md の「設定キーの一覧」が、コードが読む設定のキーと一致することを検査する。
/// 設定のキーを足す・消すときは、一覧表も直す。
@Suite struct ConfigDocsTests {
    /// このファイルから、リポジトリのルート(app/macos/Tests/HyperBufKitTests/<file> から 5 つ上)を求める。
    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private static func read(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func matches(_ pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// 文書の「設定キーの一覧」の表にあるキー。
    private static func documentedKeys() throws -> Set<String> {
        let doc = try read("docs/user/configuration.md")
        guard let start = doc.range(of: "## 設定キーの一覧") else { return [] }
        let rest = doc[start.upperBound...]
        let section = rest.range(of: "\n## ").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        return Set(try matches(#"^\| `([A-Za-z]+)`\s*\|"#, in: section))
    }

    /// 設定を読むコード(`object["…"]`、`flag("…"`、`list("…"`)が使うキー。
    private static func codeKeys() throws -> Set<String> {
        let files = [
            "app/macos/Sources/HyperBufKit/UserSettings.swift",
            "app/macos/Sources/HyperBufKit/PathPolicy.swift",
            "app/macos/Sources/HyperBufKit/EditorCommand.swift",
            "app/macos/Sources/HyperBufKit/UserKeybindings.swift",
        ]
        var keys = Set<String>()
        for file in files {
            let source = try read(file)
            keys.formUnion(try matches(#"(?:object\[|flag\(|list\()"([A-Za-z]+)""#, in: source))
        }
        return keys
    }

    @Test func documentedKeysMatchTheKeysTheCodeReads() throws {
        let documented = try Self.documentedKeys()
        let code = try Self.codeKeys()
        #expect(!documented.isEmpty)
        #expect(
            documented == code,
            "docs/user/configuration.md の一覧にないキー: \(code.subtracting(documented).sorted())、コードにないキー: \(documented.subtracting(code).sorted())"
        )
    }
}
