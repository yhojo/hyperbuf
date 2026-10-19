// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Turns the argument `FILE[:LINE[:COL]]` into an absolute path and a line. Checks the file exists and is `.md`.
public enum FileResolver {
    public struct Resolved: Equatable, Sendable {
        public let path: String
        public let line: Int?
    }

    public struct Failure: Error, Equatable {
        public let message: String
    }

    /// The column of `FILE:LINE:COL` is ignored (to match the output of many tools).
    private static let lineSuffix = try! NSRegularExpression(pattern: #"^(.+?):(\d+)(?::\d+)?$"#)

    public static func resolve(_ argument: String, cwd: String) -> Result<Resolved, Failure> {
        let fm = FileManager.default
        // A file whose name itself exists takes priority (do not break names such as a:12.md)
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
            // A directory opens its index.md, or README.md if absent (docs/dev/buffer-model.md §5.1)
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

    /// Turns a relative path into an absolute path from cwd. `.` and `..` are resolved lexically; symlinks are not.
    static func absolute(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url =
            expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
        return url.standardizedFileURL.path
    }
}
