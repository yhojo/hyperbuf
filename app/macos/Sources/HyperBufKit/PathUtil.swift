import Foundation

/// パスの正規化と比較。パスの識別・比較に使うものは、必ず `canonicalPath` で正規化する。
public enum PathUtil {
    /// `realpath(3)` による正規化。存在しなければ nil。
    ///
    /// Foundation の `resolvingSymlinksInPath()` は、`/private/var/...` を `/var/...` に直してしまう。
    /// 一方で、ディレクトリの列挙や FSEvents は `/private/var/...` を返すため、前方一致での比較が合わなくなる。
    public static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `path` が `dir` の中(または `dir` そのもの)か。区切りの境界で判定する(`/tmp` は `/tmp2` に一致しない)。
    /// 大文字小文字は区別しない(APFS の既定)。
    public static func isInside(_ path: String, _ dir: String) -> Bool {
        let p = path.lowercased()
        let d = dir.lowercased()
        if d == "/" { return true }
        return p == d || p.hasPrefix(d + "/")
    }

    /// `~` と `~/…` を、ホストのディレクトリにする。
    public static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// 親のディレクトリ。
    public static func parent(_ path: String) -> String {
        let p = (path as NSString).deletingLastPathComponent
        return p.isEmpty ? "/" : p
    }

    /// 設定のパスを正規化する: `~` を展開し、存在すれば `realpath`、なければ `.` `..` だけを解決した文字列。
    public static func normalizeConfigured(_ path: String, home: String) -> String {
        let expanded = expandTilde(path, home: home)
        if let real = canonicalPath(expanded) { return real }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
