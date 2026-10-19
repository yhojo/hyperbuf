// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

/// Checks that "List of configuration keys" in docs/user/configuration.md matches the config keys the code reads.
/// When adding or removing a settings key, also fix the table.
@Suite struct ConfigDocsTests {
    /// From this file, finds the repository root (5 levels up from app/macos/Tests/HyperBufKitTests/<file>).
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

    /// The keys in the table of "List of configuration keys" in the document.
    private static func documentedKeys() throws -> Set<String> {
        let doc = try read("docs/user/configuration.md")
        guard let start = doc.range(of: "## List of configuration keys") else { return [] }
        let rest = doc[start.upperBound...]
        let section = rest.range(of: "\n## ").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        return Set(try matches(#"^\| `([A-Za-z]+)`\s*\|"#, in: section))
    }

    /// The keys used by the code that reads settings (`object["..."]`, `flag("..."`, `list("..."`).
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
