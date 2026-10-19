// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// セッション(フレームの並び。docs/buffer-model.md §9)の保存先。全体で 1 つのファイル。
///
/// 守ること:
///  - 保存するのは、Web コアが作った、パスと位置だけのデータ(文書の内容は含まない)。大きさを制限する
///  - 中身は信頼しない(Web コアが検証する)。ここでは、JSON として読めるか、形の大枠(スロット)だけを見る
///  - 保存先は 0600、置き場所のディレクトリは 0700(利用者の作業の記録なので)
///  - 書き込みは、一時ファイルに書いてから置き換える(途中の状態を見せない)
public struct SessionStore: Sendable {
    /// 保存するデータの最大の大きさ(バイト)。
    public static let maxBytes = 4_000_000
    /// フレームの数の上限(`Cmd-1` … `Cmd-9`)。
    public static let maxFrames = 9

    public static func standardDirectory() -> URL {
        #if DEBUG
            // テスト用: 利用者の実際のセッションを使わないよう、デバッグビルドだけ、差し替えられる
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_SESSION_DIR"] {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/HyperBuf", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = SessionStore.standardDirectory()) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent("session.json") }

    /// 保存されたセッション: `{"version": 2, "active": 1, "frames": [{"slot": 1, "rect": {...}, "snapshot": {...}}]}`。
    /// なければ、壊れていれば、大きすぎれば、nil。スロットが不正・重複したフレームは、捨てる。
    public func load() -> [String: Any]? {
        guard let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= Self.maxBytes,
            let data = try? Data(contentsOf: fileURL),
            var stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            stored["version"] as? Int == 2,
            let raw = stored["frames"] as? [[String: Any]]
        else { return nil }
        var seen = Set<Int>()
        var frames: [[String: Any]] = []
        for frame in raw {
            guard let slot = frame["slot"] as? Int, (1...Self.maxFrames).contains(slot), seen.insert(slot).inserted
            else { continue }
            frames.append(frame)
        }
        stored["frames"] = frames
        return stored
    }

    /// セッションを保存する。大きすぎる・JSON にできないものは、保存しない。
    @discardableResult
    public func save(_ session: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(session),
            let data = try? JSONSerialization.data(withJSONObject: session),
            data.count <= Self.maxBytes
        else { return false }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
        let tmp = directory.appendingPathComponent(".session.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return false }
        guard (try? FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)) != nil else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        chmod(fileURL.path, 0o600)
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
