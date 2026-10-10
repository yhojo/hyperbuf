import Foundation

/// ディレクトリの列挙(入力欄の補完 `C-x C-f`、再帰の一覧 `C-x p f`、全文検索の対象)。
///
/// 対象は `*.md` とディレクトリだけ。隠しファイル(`.` で始まる)と `node_modules` は除く。
/// シンボリックリンクのディレクトリには入らない(ループ・脱出の防止)。
public enum DirectoryLister {
    public static let excludedDirectoryNames: Set<String> = ["node_modules"]
    /// 1 階層の一覧の件数の上限(仮の値。動作確認の中で決める)。
    public static let maxEntries = 2000
    /// 再帰の一覧の、ファイル数の上限。
    public static let maxTreeFiles = 20000
    /// 再帰の一覧の、時間の上限(秒)。外付けディスクやネットワークボリュームで止まらないように。
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
        /// 起点からの相対パス(昇順)。
        public var files: [String] = []
        public var truncated = false
        /// 再帰しなかった理由。
        public var refused: String?
        public var error: String?
    }

    /// ディレクトリの 1 階層。`hidden` のときだけ、隠しファイルを含める。
    public static func list(_ dir: String, hidden: Bool = false, limit: Int = maxEntries) -> Listing {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir, isDirectory: true), includingPropertiesForKeys: keys, options: [])
        else { return Listing(error: "読めません: \(dir)") }
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

    /// 再帰の一覧の起点にしてよいか。`~` と `/` は拒否する(理由を返す)。
    public static func refusalReason(for dir: String, home: String) -> String? {
        let real = PathUtil.canonicalPath(dir) ?? dir
        if real == "/" { return "ルート(/)は、再帰の起点にしません" }
        if real == (PathUtil.canonicalPath(home) ?? home) { return "ホスト(~)は、再帰の起点にしません" }
        return nil
    }

    /// ディレクトリ以下の `.md` を再帰でたどる(守り: 起点の制限、ファイル数・時間の上限)。
    public static func tree(
        _ dir: String, home: String, maxFiles: Int = maxTreeFiles, maxSeconds: Double = maxTreeSeconds
    ) -> Tree {
        if let reason = refusalReason(for: dir, home: home) { return Tree(refused: reason) }
        guard let root = PathUtil.canonicalPath(dir) else { return Tree(error: "読めません: \(dir)") }
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
