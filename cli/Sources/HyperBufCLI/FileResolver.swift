// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// 引数の `FILE[:LINE[:COL]]` を、絶対パスと行に直す。ファイルの存在と、`.md` であることを確かめる。
public enum FileResolver {
    public struct Resolved: Equatable, Sendable {
        public let path: String
        public let line: Int?
    }

    public struct Failure: Error, Equatable {
        public let message: String
    }

    /// `FILE:LINE:COL` の桁は、無視する(多くのツールの出力に合わせる)。
    private static let lineSuffix = try! NSRegularExpression(pattern: #"^(.+?):(\d+)(?::\d+)?$"#)

    public static func resolve(_ argument: String, cwd: String) -> Result<Resolved, Failure> {
        let fm = FileManager.default
        // 名前そのものが、存在するファイルなら、それを優先する(a:12.md のような名前を壊さない)
        var raw = argument
        var line: Int?
        if !fm.fileExists(atPath: absolute(raw, cwd: cwd)) {
            let range = NSRange(raw.startIndex..., in: raw)
            if let m = lineSuffix.firstMatch(in: raw, range: range),
                let fileRange = Range(m.range(at: 1), in: raw), let lineRange = Range(m.range(at: 2), in: raw)
            {
                line = Int(raw[lineRange])
                raw = String(raw[fileRange])
            }
        }
        var path = absolute(raw, cwd: cwd)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failure(Failure(message: "No such file: \(argument)"))
        }
        if isDirectory.boolValue {
            // ディレクトリは、その中の index.md、なければ README.md を開く(docs/dev/buffer-model.md §5.1)
            guard line == nil,
                let index = ["index.md", "README.md"].map({ path + "/" + $0 }).first(where: {
                    var inner: ObjCBool = false
                    return fm.fileExists(atPath: $0, isDirectory: &inner) && !inner.boolValue
                })
            else { return .failure(Failure(message: "Neither index.md nor README.md in the directory: \(argument)")) }
            path = index
        }
        guard path.hasSuffix(".md") else {
            return .failure(Failure(message: "Only .md files can be opened: \(argument)"))
        }
        if let line, line <= 0 { return .failure(Failure(message: "Invalid line number: \(argument)")) }
        return .success(Resolved(path: path, line: line))
    }

    /// 相対パスを、cwd からの絶対パスにする。`.` と `..` は字句的に解決し、シンボリックリンクは解決しない。
    static func absolute(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url =
            expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
        return url.standardizedFileURL.path
    }
}
