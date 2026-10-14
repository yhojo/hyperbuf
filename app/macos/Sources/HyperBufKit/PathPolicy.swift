// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// ファイルへのアクセスの判定(docs/project-model.md §5): 許可パスと警告パス。
///
///  1. どちらにも一致しなければ → 開く
///  2. 一致するものがあれば、一番長く一致したものが勝つ(許可 → 開く、警告 → 確認)
///  3. 許可と警告が同じパスで重なれば、安全側の警告(設定の問題として報告する)
///
/// パスは正規化(`realpath`、シンボリックリンクは実体)したうえで、区切りの境界で照合する。
public struct PathPolicy: Sendable {
    public enum Decision: Sendable, Equatable {
        case allow
        /// 警告パスのファイル。確認が要る。承認されたら `remember` を記憶する(アプリが提案したもの)。
        case confirm(remember: String)
    }

    /// 警告パスの既定(ホスト配下の機微な場所を含む)。
    public static func defaultWarn(home: String) -> [String] {
        [
            "/usr", "/opt", "/tmp", "/var", "/etc", "/System", "/Library",
            "\(home)/.ssh", "\(home)/.aws", "\(home)/.gnupg", "\(home)/Library",
        ]
    }

    /// 許可パスの既定(iCloud Drive。`~/Library` の警告より、長い一致が勝つ)。
    public static func defaultAllow(home: String) -> [String] {
        ["\(home)/Library/Mobile Documents"]
    }

    public let home: String
    public private(set) var warn: [String]
    public private(set) var allow: [String]
    /// 設定の問題(`C-h b` の「設定の問題」に出す)。
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
        // 許可と警告が同じパスなら、安全側(警告)にして、報告する
        let both = Set(self.warn.map { $0.lowercased() }).intersection(self.allow.map { $0.lowercased() })
        for path in both.sorted() {
            self.problems.append(
                "The same path is in both allowPaths and warnPaths (treated as a warning path): \(path)")
        }
        self.allow.removeAll { both.contains($0.lowercased()) }
    }

    /// 設定ファイル(`config.json`)の `warnPaths` / `allowPaths`。なければ既定。不正な項目は無視して、理由を記録する。
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

    /// 判定する。`path` は正規化済みの絶対パス。`remembered` は、承認して記憶した場所(許可として働く)。
    public func decide(_ path: String, remembered: RememberedPaths) -> Decision {
        var best: (length: Int, allowed: Bool)?
        func consider(_ dir: String, allowed: Bool, explicit: Bool = false) {
            guard PathUtil.isInside(path, dir) else { return }
            // 承認して記憶した場所(explicit)は、同じ長さの警告パスより優先する(利用者が明示的に許可した)
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

    /// 許可パス(設定・記憶を含む)に明示的に含まれるか。警告パスとの比較はしない(URL スキーム経由の判定に使う)。
    public func isExplicitlyAllowed(_ path: String, remembered: RememberedPaths) -> Bool {
        if allow.contains(where: { PathUtil.isInside(path, $0) }) { return true }
        return remembered.all.contains { PathUtil.isInside(path, PathUtil.canonicalPath($0) ?? $0) }
    }

    /// 承認されたときに記憶するもの。ファイルのディレクトリ。ただし、それが警告パスそのもの、または
    /// その上位になる場合は、ディレクトリ全体を許可してしまうので、ファイル単体にする。
    public func rememberTarget(for file: String) -> String {
        let dir = PathUtil.parent(file)
        for w in warn where PathUtil.isInside(w, dir) { return file }
        return dir
    }
}
