// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// 設定ファイル(`config.json`)の、スカラーと一覧の設定。docs/configuration.md。
/// 型が違うものは、既定のままにして、理由を `problems` に残す(`C-h b` の「設定の問題」に出る)。
public struct UserSettings: Sendable, Equatable {
    /// 前回の状態を復元し、保存するか。
    public var restoreSession = true
    /// 数式の中の `\_` を `_` に戻すか(Marked 2 などとの互換)。
    public var mathUnescapeUnderscore = true
    /// ファイルが外部で更新されたとき、変更箇所の先頭へスクロールするか。
    public var followUpdates = false
    /// 確認なしにブラウザで開く URL のパターン(`*` は、任意の文字列)。
    public var trustedUrls: [String] = []
    public var problems: [String] = []

    public static let maxTrustedUrls = 200
    public static let maxPatternLength = 500

    public init() {}

    public static func load(from url: URL = EditorConfig.configURL()) -> UserSettings {
        var settings = UserSettings()
        guard let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return settings }
        func flag(_ key: String, _ current: Bool) -> Bool {
            guard let raw = object[key] else { return current }
            // JSON の数値(1 / 0)を、真偽値として受け取らない(`as? Bool` は、NSNumber の 1 を true にしてしまう)
            if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            settings.problems.append("\(key) は true / false にしてください(無視します)")
            return current
        }
        settings.restoreSession = flag("restoreSession", settings.restoreSession)
        settings.mathUnescapeUnderscore = flag("mathUnescapeUnderscore", settings.mathUnescapeUnderscore)
        settings.followUpdates = flag("followUpdates", settings.followUpdates)
        if let raw = object["trustedUrls"] {
            if let items = raw as? [Any], items.count <= maxTrustedUrls {
                for item in items {
                    guard let pattern = item as? String, !pattern.isEmpty, pattern.count <= maxPatternLength,
                        let scheme = pattern.split(separator: ":", maxSplits: 1).first,
                        ["http", "https"].contains(scheme.lowercased())
                    else {
                        settings.problems.append("trustedUrls に不正な項目があります(http:// または https:// で始めてください。無視します)")
                        continue
                    }
                    settings.trustedUrls.append(pattern)
                }
            } else {
                settings.problems.append("trustedUrls は文字列の配列(\(maxTrustedUrls) 件まで)にしてください(無視します)")
            }
        }
        return settings
    }
}
