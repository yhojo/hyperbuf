// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Project root search (docs/dev/buffer-model.md §6). Like Emacs' `project.el`,
/// it goes up from the buffer's base directory to its parents and takes the first directory with a VCS marker as the root.
public enum ProjectRoot {
    /// VCS markers (a directory or a file; `.git` is a file in a worktree / submodule).
    public static let markers = [".git", ".hg", ".svn", ".bzr", "_darcs", ".jj"]

    /// The project root of `dir` (a normalized absolute path).
    ///
    /// - Stops going up on reaching `~` or `/` (the whole host never becomes the root).
    /// - A directory that exactly matches `ignore` (`projectIgnorePaths`) is skipped even if it has a marker.
    /// - If none is found, `dir` itself (`default-directory`).
    public static func find(from dir: String, home: String, ignore: [String] = []) -> String {
        markedRoot(from: dir, home: home, ignore: ignore) ?? (PathUtil.canonicalPath(dir) ?? dir)
    }

    /// Returns the root only when a VCS marker is found by the same search as `find` (nil if none is found).
    public static func markedRoot(from dir: String, home: String, ignore: [String] = []) -> String? {
        let start = PathUtil.canonicalPath(dir) ?? dir
        let stops = Set([PathUtil.canonicalPath(home) ?? home, "/"].map { $0.lowercased() })
        let skipped = Set(ignore.map { PathUtil.normalizeConfigured($0, home: home).lowercased() })
        var current = start
        while !stops.contains(current.lowercased()) {
            if !skipped.contains(current.lowercased()), hasMarker(current) { return current }
            let up = PathUtil.parent(current)
            if up == current { break }
            current = up
        }
        return nil
    }

    private static func hasMarker(_ dir: String) -> Bool {
        markers.contains { FileManager.default.fileExists(atPath: dir + "/" + $0) }
    }
}
