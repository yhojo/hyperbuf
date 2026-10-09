import CryptoKit
import Foundation

/// プロジェクトごとのセッション(window の配置・参照履歴・閲覧位置など)の保存先。
///
/// 守ること:
///  - 保存するのは、Web コアが作った、パスと位置だけのデータ(文書の内容は含まない)。大きさを制限する
///  - 中身は信頼しない(Web コアが検証する)。ここでは、JSON として読めるかだけを見る
///  - 保存先は 0600、置き場所のディレクトリは 0700(利用者の作業の記録なので)
///  - 書き込みは、一時ファイルに書いてから置き換える(途中の状態を見せない)
public struct SessionStore: Sendable {
    /// 保存するデータの最大の大きさ(バイト)。
    public static let maxBytes = 1_000_000

    public static func standardDirectory() -> URL {
        #if DEBUG
            // テスト用: 利用者の実際のセッションを使わないよう、デバッグビルドだけ、差し替えられる
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_SESSION_DIR"] {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/HyperBuf/sessions", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = SessionStore.standardDirectory()) {
        self.directory = directory
    }

    /// プロジェクトのルート(正規化済みの絶対パス)から決まる、ファイル名。
    func fileURL(for project: Project) -> URL {
        let digest = SHA256.hash(data: Data(project.root.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }

    /// 保存されたセッション(JSON)。なければ、壊れていれば、大きすぎれば、nil。
    public func load(for project: Project) -> Any? {
        let url = fileURL(for: project)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= Self.maxBytes,
            let data = try? Data(contentsOf: url),
            let stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            stored["project"] as? String == project.root.path
        else { return nil }
        return stored["snapshot"]
    }

    /// セッション(JSON)を保存する。大きすぎる・JSON にできないものは、保存しない。
    @discardableResult
    public func save(_ snapshot: Any, for project: Project) -> Bool {
        guard JSONSerialization.isValidJSONObject(["snapshot": snapshot]),
            let data = try? JSONSerialization.data(
                withJSONObject: ["v": 1, "project": project.root.path, "snapshot": snapshot] as [String: Any]),
            data.count <= Self.maxBytes
        else { return false }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
        let tmp = directory.appendingPathComponent(".session.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return false }
        let url = fileURL(for: project)
        guard (try? FileManager.default.replaceItemAt(url, withItemAt: tmp)) != nil else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        chmod(url.path, 0o600)
        return true
    }
}

/// 設定ファイル(`config.json`)の、セッションに関する項目。
public enum SessionSettings {
    /// `restoreSession`: 前回の状態を復元し、保存するか。既定は true(`false` のときだけ、無効)。
    public static func restoreEnabled(from url: URL = EditorConfig.configURL()) -> Bool {
        guard let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let value = object["restoreSession"] as? Bool
        else { return true }
        return value
    }
}
