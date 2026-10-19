// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Judgment of file access (docs/dev/file-access.md): allow paths and warn paths.
///
///  1. If neither matches -> open
///  2. If any match, the longest match wins (allow -> open, warn -> confirm)
///  3. If allow and warn overlap on the same path, the safe side (warn) wins (reported as a config problem)
///
/// Paths are normalized (`realpath`; symbolic links resolved) and matched on separator boundaries.
public struct PathPolicy: Sendable {
    public enum Decision: Sendable, Equatable {
        case allow
        /// A file under a warn path. Confirmation is needed. If approved, `remember` is remembered (proposed by the app).
        case confirm(remember: String)
    }

    /// Default warn paths (including sensitive places under the host's home directory).
    public static func defaultWarn(home: String) -> [String] {
        [
            "/usr", "/opt", "/tmp", "/var", "/etc", "/System", "/Library",
            "\(home)/.ssh", "\(home)/.aws", "\(home)/.gnupg", "\(home)/Library",
        ]
    }

    /// Default allow paths (iCloud Drive; a longer match beats the `~/Library` warning).
    public static func defaultAllow(home: String) -> [String] {
        ["\(home)/Library/Mobile Documents"]
    }

    public let home: String
    public private(set) var warn: [String]
    public private(set) var allow: [String]
    /// Config problems (shown as "configuration problems" in `C-h b`).
    public private(set) var problems: [String]

    public init(home: String, warn: [String]? = nil, allow: [String]? = nil, problems: [String] = []) {
        self.home = home
        self.warn = (warn ?? PathPolicy.defaultWarn(home: home)).map {
            PathUtil.normalizeConfigured($0, home: home)
        }
        self.allow = (allow ?? PathPolicy.defaultAllow(home: home)).map {
            PathUtil.normalizeConfigured($0, home: home)
        }
        self.problems = problems
        // If allow and warn are the same path, take the safe side (warn) and report it
        let both = Set(self.warn.map { $0.lowercased() }).intersection(self.allow.map { $0.lowercased() })
        for path in both.sorted() {
            self.problems.append(
                "The same path is in both allowPaths and warnPaths (treated as a warning path): \(path)")
        }
        self.allow.removeAll { both.contains($0.lowercased()) }
    }

    /// `warnPaths` / `allowPaths` of the config file (`config.json`). Defaults if absent. Invalid entries are ignored and the reason recorded.
    public static func load(from url: URL, home: String) -> PathPolicy {
        var problems: [String] = []
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
            let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        {
            object = parsed
        }
        func list(_ key: String) -> [String]? {
            guard let raw = object[key] else { return nil }
            guard let items = raw as? [Any] else {
                problems.append("\(key) must be an array of strings (ignored)")
                return nil
            }
            var out: [String] = []
            for item in items {
                guard let path = item as? String, !path.isEmpty, path.count <= 1024, !path.contains("\0") else {
                    problems.append("\(key) has an invalid entry (ignored)")
                    continue
                }
                guard path.hasPrefix("/") || path.hasPrefix("~/") || path == "~" else {
                    problems.append("\(key): write an absolute path (or ~/…): \(path)")
                    continue
                }
                out.append(path)
            }
            return out
        }
        let warn = list("warnPaths")
        let allow = list("allowPaths")
        return PathPolicy(home: home, warn: warn, allow: allow, problems: problems)
    }

    /// Judges. `path` is a normalized absolute path. `remembered` are places approved and remembered (they act as allow).
    public func decide(_ path: String, remembered: RememberedPaths) -> Decision {
        var best: (length: Int, allowed: Bool)?
        func consider(_ dir: String, allowed: Bool, explicit: Bool = false) {
            guard PathUtil.isInside(path, dir) else { return }
            // A remembered place (explicit) beats a warn path of the same length (the user explicitly allowed it)
            let length = (dir == "/" ? 0 : dir.count) * 2 + (explicit ? 1 : 0)
            if let current = best {
                if length > current.length || (length == current.length && !allowed) { best = (length, allowed) }
            } else {
                best = (length, allowed)
            }
        }
        for dir in warn { consider(dir, allowed: false) }
        for dir in allow { consider(dir, allowed: true) }
        for dir in remembered.all { consider(PathUtil.canonicalPath(dir) ?? dir, allowed: true, explicit: true) }
        guard let best, !best.allowed else { return .allow }
        return .confirm(remember: rememberTarget(for: path))
    }

    /// Whether it is explicitly under an allow path (including config and remembered). Not compared with warn paths (used for the URL scheme route).
    public func isExplicitlyAllowed(_ path: String, remembered: RememberedPaths) -> Bool {
        if allow.contains(where: { PathUtil.isInside(path, $0) }) { return true }
        return remembered.all.contains { PathUtil.isInside(path, PathUtil.canonicalPath($0) ?? $0) }
    }

    /// What to remember on approval: the file's directory. But if that is a warn path itself, or
    /// an ancestor of one, it would allow the whole directory, so use the single file instead.
    public func rememberTarget(for file: String) -> String {
        let dir = PathUtil.parent(file)
        for w in warn where PathUtil.isInside(w, dir) { return file }
        return dir
    }
}
