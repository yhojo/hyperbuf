// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// The Git branch name shown in the mode line. Reads `HEAD` directly without external commands (docs/dev/buffer-model.md §6.9).
///
/// Reads only the first line of `HEAD` in the project root's `.git` (a directory, or the `gitdir:` file of a worktree / submodule).
/// The repository is untrusted input, so size, format and length are limited.
public enum VCSBranch {
    /// Upper limit on the amount read (bytes).
    static let maxBytes = 4096
    /// Upper limit on the length of the displayed branch name (characters). Longer ones are truncated at the end.
    static let maxLength = 80
    /// Number of digits of the short hash shown for a detached HEAD.
    static let shortHashLength = 7

    /// The branch name for `dir`. nil if there is no Git root or `HEAD` cannot be read or has the wrong form.
    /// A detached HEAD gives a short hash.
    public static func read(from dir: String, home: String, ignore: [String] = []) -> String? {
        guard let root = ProjectRoot.markedRoot(from: dir, home: home, ignore: ignore),
            let gitDir = gitDirectory(root)
        else { return nil }
        guard let head = readSmallFile(gitDir + "/HEAD") else { return nil }
        return parse(head)
    }

    /// Derives the display name from the contents of `HEAD` (the first line).
    static func parse(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if line.hasPrefix("ref:") {
            var ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            for prefix in ["refs/heads/", "refs/"] where ref.hasPrefix(prefix) {
                ref.removeFirst(prefix.count)
                break
            }
            return sanitize(ref)
        }
        let isHash =
            (line.count == 40 || line.count == 64)
            && line.allSatisfy { $0.isASCII && $0.isHexDigit }
        return isHash ? String(line.prefix(shortHashLength)) : nil
    }

    /// Drops anything containing control characters and truncates anything too long.
    private static func sanitize(_ name: String) -> String? {
        guard !name.isEmpty, !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return name.count > maxLength ? String(name.prefix(maxLength - 1)) + "…" : name
    }

    /// The root's `.git`: itself if a directory; if a `gitdir: <path>` file, what it points to.
    private static func gitDirectory(_ root: String) -> String? {
        let dotGit = root + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }
        guard let text = readSmallFile(dotGit),
            let line = text.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:")
        else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, !target.contains("\0") else { return nil }
        return target.hasPrefix("/") ? target : root + "/" + target
    }

    /// Reads only a regular file, up to the first `maxBytes` (so it does not hang on FIFOs, devices, etc.).
    private static func readSmallFile(_ path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
