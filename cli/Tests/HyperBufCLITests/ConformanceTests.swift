// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol
import Testing

@testable import HyperBufCLI

/// protocol/examples/cli-args.json の例を、実際のファイルを作って検証する(Swift・Emacs が共有する例)。
@Suite struct CLIConformanceTests {
    @Test func cliArgsExamples() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("protocol/examples/cli-args.json")
        let cases = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(!cases.isEmpty)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let temp = try TempDir()
            defer { temp.remove() }
            func expand(_ text: String) -> String { text.replacingOccurrences(of: "${TMP}", with: temp.path) }
            for file in item["files"] as? [String] ?? [] { try temp.write(file, "# x\n") }
            let cwd = expand(item["cwd"] as? String ?? "${TMP}")
            try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
            var arguments = (item["args"] as? [String] ?? []).map(expand)
            let output = Output()

            if let expected = item["request"] as? [String: Any] {
                arguments.insert("--print-url", at: 0)
                let code = CLI.run(arguments, output.environment(cwd: cwd, socketPath: "/nonexistent"))
                #expect(code == 0, "\(name): \(output.err)")
                let urlString = try #require(output.out.first, "\(name)")
                let parsed = try #require(URL(string: urlString))
                guard case .success(let request) = OpenURL.parse(parsed) else {
                    Issue.record("\(name): URL を解釈できない: \(urlString)")
                    continue
                }
                #expect(request.op == expected["op"] as? String, "\(name)")
                #expect(request.path == (expected["path"] as? String).map(expand), "\(name)")
                #expect(request.line == expected["line"] as? Int, "\(name)")
                #expect(request.anchor == expected["anchor"] as? String, "\(name)")
                #expect(request.project == (expected["project"] as? String).map(expand), "\(name)")
                #expect(request.target == expected["target"] as? String, "\(name)")
            } else if let exit = item["exit"] as? Int {
                let code = CLI.run(arguments, output.environment(cwd: cwd, socketPath: "/nonexistent"))
                #expect(Int(code) == exit, "\(name): \(output.err)")
            }
        }
    }
}
