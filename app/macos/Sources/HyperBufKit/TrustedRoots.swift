import Foundation

/// 利用者が承認した「信頼するルート」(プロジェクトの外で、読んでよいディレクトリ)。永続化する。
///
/// 守ること:
///  - 追加できるのは、アプリ自身が提案し、利用者がミニバッファで承認したルートだけ(Web 側から任意のルートは足せない)
///  - 保存先は 0600、置き場所のディレクトリは 0700(文書の一部を含まないが、利用者の作業場所が分かるため)
public final class TrustedRoots: @unchecked Sendable {
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
    private var roots: [String]

    public init(url: URL = TrustedRoots.standardURL()) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            roots = stored.roots
        } else {
            roots = []
        }
    }

    public var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return roots
    }

    /// `path`(絶対パス)が、信頼するルートの内側にあるか。シンボリックリンクは解決して比べる。
    public func contains(_ path: String) -> Bool {
        guard let real = Project.canonicalPath(path) else { return false }
        return all.contains { root in
            guard let realRoot = Project.canonicalPath(root) else { return false }
            return real == realRoot || real.hasPrefix(realRoot + "/")
        }
    }

    /// ルートを足して保存する。ディレクトリが存在しないものは足さない。
    @discardableResult
    public func add(_ root: String) -> Bool {
        guard let real = Project.canonicalPath(root) else { return false }
        lock.lock()
        defer { lock.unlock() }
        if !roots.contains(real) {
            roots.append(real)
            save()
        }
        return true
    }

    private func save() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir.path, 0o700)
        guard let data = try? JSONEncoder().encode(Stored(v: 1, roots: roots)) else { return }
        // 一時ファイルに 0600 で書いてから、置き換える(書き込み途中のファイルを見せない)
        let tmp = dir.appendingPathComponent(".trusted-roots.\(UUID().uuidString).tmp")
        if FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            chmod(url.path, 0o600)
        }
    }
}
