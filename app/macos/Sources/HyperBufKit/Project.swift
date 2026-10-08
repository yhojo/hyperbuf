import Foundation

public enum ProjectError: Error, Equatable {
    /// プロジェクトの外を指している(`..`、シンボリックリンクによる脱出を含む)。
    case outside
    case notMarkdown
    case notFound
    /// 画像以外のリソース。
    case unsupportedResource
    case unreadable
}

/// プロジェクト(Markdown の置き場)。すべてのファイルアクセスは、ここを通る。
///
/// 守ること:
///  - ルートの内側のファイルだけを扱う。シンボリックリンクは解決したうえで、再度ルートの内側かを確かめる
///  - 読めるのは `.md` と、画像(拡張子で限る)だけ
///  - 一覧から、隠しファイル・隠しディレクトリと `node_modules` を除く(`.gitignore` は解釈しない)
public struct Project: Sendable {
    /// 既定で除くディレクトリ名。パッケージごとに README.md が大量にあるため。
    public static let excludedDirectoryNames: Set<String> = ["node_modules"]

    /// シンボリックリンク解決済みのルート(`realpath`)。
    public let root: URL

    public init(root: URL) {
        let real = Project.canonicalPath(root.path) ?? root.standardizedFileURL.path
        self.root = URL(fileURLWithPath: real, isDirectory: true)
    }

    public var name: String { root.lastPathComponent }

    /// `realpath(3)` による正規化。存在しなければ nil。
    ///
    /// Foundation の `resolvingSymlinksInPath()` は、`/private/var/...` を `/var/...` に直してしまう。
    /// 一方で、ディレクトリの列挙や FSEvents は `/private/var/...` を返すため、前方一致での比較が合わなくなる。
    /// パスの比較に使うものは、必ずこの関数で正規化する。
    public static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// 相対パスを、ルートの内側の実ファイルの URL にする。
    public func resolve(_ relative: String) throws -> URL {
        // 絶対パス・空・NUL・制御文字・`..` は、プロジェクト内の相対パスとして不正
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\0"),
            !relative.unicodeScalars.contains(where: { $0.value < 0x20 }),
            !relative.split(separator: "/").contains("..")
        else { throw ProjectError.outside }
        guard let real = Project.canonicalPath(root.appendingPathComponent(relative).path) else {
            throw ProjectError.notFound
        }
        // シンボリックリンクを解決したうえで、再度ルートの内側かを確かめる
        guard real.hasPrefix(root.path + "/") else { throw ProjectError.outside }
        return URL(fileURLWithPath: real)
    }

    /// プロジェクト内の Markdown の相対パス(昇順)。
    public func markdownFiles() -> [String] {
        var out: [String] = []
        collect(directory: root, prefix: "", into: &out)
        return out.sorted()
    }

    /// ディレクトリを再帰的にたどる。シンボリックリンクのディレクトリには入らない(ループ・脱出の防止)。
    private func collect(directory: URL, prefix: String, into out: inout [String]) {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            let isDirectory = (try? entry.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            if isDirectory {
                if Project.excludedDirectoryNames.contains(name) { continue }
                collect(directory: entry, prefix: prefix + name + "/", into: &out)
            } else if entry.pathExtension == "md" {
                out.append(prefix + name)
            }
        }
    }

    public func readMarkdown(_ relative: String) throws -> String {
        guard relative.hasSuffix(".md") else { throw ProjectError.notMarkdown }
        let file = try resolve(relative)
        guard let data = try? Data(contentsOf: file) else { throw ProjectError.unreadable }
        return String(decoding: data, as: UTF8.self)
    }

    /// 文書から参照される画像。画像の拡張子だけを返す。
    public func readResource(_ relative: String) throws -> (data: Data, mime: String) {
        let ext = (relative as NSString).pathExtension.lowercased()
        guard MimeType.imageExtensions.contains(ext) else { throw ProjectError.unsupportedResource }
        let file = try resolve(relative)
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { throw ProjectError.unreadable }
        return (data, MimeType.forExtension(ext))
    }
}
