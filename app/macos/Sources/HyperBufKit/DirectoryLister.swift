// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Directory enumeration (input completion `C-x C-f`, recursive listing `C-x p f`, the targets of full-text search).
///
/// Only `*.md` and directories are targeted. Hidden files (starting with `.`) and `node_modules` are excluded.
/// Symbolic-link directories are not entered (prevents loops and escapes).
public enum DirectoryLister {
    public static let excludedDirectoryNames: Set<String> = ["node_modules"]
    /// Upper limit on the count of a one-level listing (a provisional value; to be decided during testing).
    public static let maxEntries = 2000
    /// Upper limit on the file count of a recursive listing.
    public static let maxTreeFiles = 20000
    /// Upper limit on the time (seconds) of a recursive listing, so it does not hang on external disks or network volumes.
    public static let maxTreeSeconds = 3.0

    public struct Entry: Sendable, Equatable {
        public let name: String
        public let dir: Bool
    }

    public struct Listing: Sendable, Equatable {
        public var entries: [Entry] = []
        public var truncated = false
        public var error: String?
    }

    public struct Tree: Sendable, Equatable {
        /// Path relative to the base (ascending).
        public var files: [String] = []
        public var truncated = false
        /// The reason it did not recurse.
        public var refused: String?
        public var error: String?
    }

    /// One level of a directory. Hidden files are included only for `hidden`.
    public static func list(_ dir: String, hidden: Bool = false, limit: Int = maxEntries) -> Listing {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir, isDirectory: true), includingPropertiesForKeys: keys, options: [])
        else { return Listing(error: "Cannot read: \(dir)") }
        var result = Listing()
        for url in urls {
            let name = url.lastPathComponent
            if !hidden && name.hasPrefix(".") { continue }
            let isDirectory = (try? url.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            if isDirectory {
                if !hidden && excludedDirectoryNames.contains(name) { continue }
            } else if url.pathExtension != "md" {
                continue
            }
            if result.entries.count >= limit {
                result.truncated = true
                break
            }
            result.entries.append(Entry(name: name, dir: isDirectory))
        }
        return result
    }

    /// Whether it may be the base of a recursive listing. `~` and `/` are refused (the reason is returned).
    public static func refusalReason(for dir: String, home: String) -> String? {
        let real = PathUtil.canonicalPath(dir) ?? dir
        if real == "/" { return "The root (/) cannot be a recursion root" }
        if real == (PathUtil.canonicalPath(home) ?? home) { return "The home directory (~) cannot be a recursion root" }
        return nil
    }

    /// Recursively traverses `.md` files below a directory (safeguards: base restriction, limits on file count and time).
    public static func tree(
        _ dir: String, home: String, maxFiles: Int = maxTreeFiles, maxSeconds: Double = maxTreeSeconds
    ) -> Tree {
        if let reason = refusalReason(for: dir, home: home) { return Tree(refused: reason) }
        guard let root = PathUtil.canonicalPath(dir) else { return Tree(error: "Cannot read: \(dir)") }
        let deadline = Date().addingTimeInterval(maxSeconds)
        var result = Tree()
        collect(
            URL(fileURLWithPath: root, isDirectory: true), prefix: "", deadline: deadline, max: maxFiles, into: &result)
        result.files.sort()
        return result
    }

    private static func collect(
        _ directory: URL, prefix: String, deadline: Date, max: Int, into result: inout Tree
    ) {
        if result.truncated { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return }
        for entry in entries {
            if Date() > deadline || result.files.count >= max {
                result.truncated = true
                return
            }
            let name = entry.lastPathComponent
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if values?.isSymbolicLink == true || excludedDirectoryNames.contains(name) { continue }
                collect(entry, prefix: prefix + name + "/", deadline: deadline, max: max, into: &result)
            } else if entry.pathExtension == "md" {
                result.files.append(prefix + name)
            }
        }
    }
}
