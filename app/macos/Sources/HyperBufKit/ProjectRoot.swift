// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// プロジェクト・ルートの探索(docs/buffer-model.md §6)。Emacs の `project.el` と同じく、
/// バッファの基準のディレクトリから親へさかのぼり、最初に VCS の目印があるディレクトリを、ルートにする。
public enum ProjectRoot {
    /// VCS の目印(ディレクトリ、またはファイル。`.git` は worktree・submodule ではファイル)。
    public static let markers = [".git", ".hg", ".svn", ".bzr", "_darcs", ".jj"]

    /// `dir` のプロジェクト・ルート(正規化した絶対パス)。
    ///
    /// - `~` と `/` に達したらさかのぼりを止める(ホスト全体がルートにならない)。
    /// - `ignore`(`projectIgnorePaths`)に完全一致するディレクトリは、目印があっても飛ばす。
    /// - 見つからなければ `dir` 自身(`default-directory`)。
    public static func find(from dir: String, home: String, ignore: [String] = []) -> String {
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
        return start
    }

    private static func hasMarker(_ dir: String) -> Bool {
        markers.contains { FileManager.default.fileExists(atPath: dir + "/" + $0) }
    }
}
