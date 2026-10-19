// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Path normalization and comparison. Anything used to identify or compare paths must be normalized with `canonicalPath`.
public enum PathUtil {
    /// Normalization via `realpath(3)`. nil if it does not exist.
    ///
    /// Foundation's `resolvingSymlinksInPath()` rewrites `/private/var/...` to `/var/...`.
    /// But directory enumeration and FSEvents return `/private/var/...`, so prefix comparison would no longer match.
    public static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Whether `path` is inside `dir` (or is `dir`). Judged on separator boundaries (`/tmp` does not match `/tmp2`).
    /// Case-insensitive (the APFS default).
    public static func isInside(_ path: String, _ dir: String) -> Bool {
        let p = path.lowercased()
        let d = dir.lowercased()
        if d == "/" { return true }
        return p == d || p.hasPrefix(d + "/")
    }

    /// Turns `~` and `~/...` into the host's home directory.
    public static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// The parent directory.
    public static func parent(_ path: String) -> String {
        let p = (path as NSString).deletingLastPathComponent
        return p.isEmpty ? "/" : p
    }

    /// Normalizes a configured path: expands `~`; `realpath` if it exists, otherwise a string with only `.` and `..` resolved.
    public static func normalizeConfigured(_ path: String, home: String) -> String {
        let expanded = expandTilde(path, home: home)
        if let real = canonicalPath(expanded) { return real }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
