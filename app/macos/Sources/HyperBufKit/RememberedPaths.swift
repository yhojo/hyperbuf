import Foundation

/// 利用者が承認して記憶した、警告パスの下で読んでよい場所(ディレクトリまたはファイル)。永続化する。
/// (以前の「信頼するルート」。保存先のファイルと形式は、そのまま引き継ぐ。)
///
/// 守ること:
///  - 追加できるのは、アプリ自身が提案し、利用者がミニバッファで承認したものだけ(Web 側から任意のパスは足せない)
///  - 保存先は 0600、置き場所のディレクトリは 0700(利用者の作業場所が分かるため)
public final class RememberedPaths: @unchecked Sendable {
    public static func standardURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/HyperBuf/trusted-roots.json")
    }

    private struct Stored: Codable {
        var v: Int
        var roots: [String]
    }

    private let url: URL
    private let lock = NSLock()
    private var paths: [String]

    public init(url: URL = RememberedPaths.standardURL()) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            paths = stored.roots
        } else {
            paths = []
        }
    }

    public var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    /// `path`(絶対パス)が、記憶した場所の内側(または、そのもの)か。
    public func contains(_ path: String) -> Bool {
        let real = PathUtil.canonicalPath(path) ?? path
        return all.contains { PathUtil.isInside(real, PathUtil.canonicalPath($0) ?? $0) }
    }

    /// 場所を足して保存する。存在しないものは足さない。
    @discardableResult
    public func add(_ path: String) -> Bool {
        guard let real = PathUtil.canonicalPath(path) else { return false }
        lock.lock()
        defer { lock.unlock() }
        if !paths.contains(real) {
            paths.append(real)
            save()
        }
        return true
    }

    /// 記憶を取り消して保存する。
    @discardableResult
    public func remove(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = paths.firstIndex(of: path) else { return false }
        paths.remove(at: index)
        save()
        return true
    }

    private func save() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir.path, 0o700)
        guard let data = try? JSONEncoder().encode(Stored(v: 1, roots: paths)) else { return }
        // 一時ファイルに 0600 で書いてから、置き換える(書き込み途中のファイルを見せない)
        let tmp = dir.appendingPathComponent(".trusted-roots.\(UUID().uuidString).tmp")
        if FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            chmod(url.path, 0o600)
        }
    }
}
