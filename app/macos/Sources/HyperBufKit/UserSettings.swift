// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// アプリの外観。`system` は、OS の設定に従う。`light` / `dark` は、OS の設定に関係なく、固定する。
public enum Appearance: String, Sendable, CaseIterable {
    case system, light, dark
}

/// フレーム(ウィンドウ)全体の透明度。Emacs の `(set-frame-parameter nil 'alpha '(80 65))` と同じ意味。
/// 値は、パーセント(不透明が 100)。`active` は前面(キー)のフレーム、`inactive` は、それ以外。
public struct WindowAlpha: Sendable, Equatable {
    public var active: Int
    public var inactive: Int

    public static let opaque = WindowAlpha(active: 100, inactive: 100)
    /// 透明度として受け付ける範囲(これより低いと、ウィンドウが、見えなくなる)。
    public static let range = 10...100

    public init(active: Int, inactive: Int) {
        self.active = active
        self.inactive = inactive
    }

    /// `NSWindow.alphaValue` にする値(0〜1)。アクセシビリティの「透明度を下げる」がオンなら、常に不透明。
    public func value(isKey: Bool, reduceTransparency: Bool) -> Double {
        reduceTransparency ? 1 : Double(isKey ? active : inactive) / 100
    }
}

/// 設定ファイル(`config.json`)の、スカラーと一覧の設定。docs/configuration.md。
/// 型が違うものは、既定のままにして、理由を `problems` に残す(`C-h b` の「設定の問題」に出る)。
public struct UserSettings: Sendable, Equatable {
    /// 前回の状態を復元し、保存するか。
    public var restoreSession = true
    /// 数式の中の `\_` を `_` に戻すか(Marked 2 などとの互換)。
    public var mathUnescapeUnderscore = true
    /// ファイルが外部で更新されたとき、変更箇所の先頭へスクロールするか。
    public var followUpdates = false
    /// 外観(ライト / ダーク)。既定は、OS に従う。
    public var appearance = Appearance.system
    /// フレームの透明度(既定は、透過なし)。
    public var alpha = WindowAlpha.opaque
    /// 確認なしにブラウザで開く URL のパターン(`*` は、任意の文字列)。
    public var trustedUrls: [String] = []
    /// プロジェクト・ルートにしないディレクトリ(`~/…` または絶対パス。完全一致)。docs/project-model.md §14.3。
    public var projectIgnorePaths: [String] = []
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
            settings.problems.append("\(key) must be true or false (ignored)")
            return current
        }
        settings.restoreSession = flag("restoreSession", settings.restoreSession)
        settings.mathUnescapeUnderscore = flag("mathUnescapeUnderscore", settings.mathUnescapeUnderscore)
        settings.followUpdates = flag("followUpdates", settings.followUpdates)
        if let raw = object["appearance"] {
            if let name = raw as? String, let value = Appearance(rawValue: name) {
                settings.appearance = value
            } else {
                settings.problems.append("appearance must be \"system\", \"light\" or \"dark\" (ignored)")
            }
        }
        if let raw = object["alpha"] {
            // 2 つの整数(パーセント)。JSON の真偽値(NSNumber)は、整数として受け取らない
            func percent(_ value: Any) -> Int? {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                    number.doubleValue == Double(number.intValue), WindowAlpha.range.contains(number.intValue)
                else { return nil }
                return number.intValue
            }
            if let items = raw as? [Any], items.count == 2, let active = percent(items[0]),
                let inactive = percent(items[1])
            {
                settings.alpha = WindowAlpha(active: active, inactive: inactive)
            } else {
                settings.problems.append(
                    "alpha must be [active, inactive], two integers from \(WindowAlpha.range.lowerBound) to \(WindowAlpha.range.upperBound) (ignored)"
                )
            }
        }
        if let raw = object["projectIgnorePaths"] {
            if let items = raw as? [Any] {
                for item in items {
                    guard let path = item as? String, !path.isEmpty, path.count <= maxPatternLength,
                        !path.contains("\0"), path.hasPrefix("/") || path == "~" || path.hasPrefix("~/")
                    else {
                        settings.problems.append(
                            "projectIgnorePaths has an invalid entry (write an absolute path or ~/…; ignored)")
                        continue
                    }
                    settings.projectIgnorePaths.append(path)
                }
            } else {
                settings.problems.append("projectIgnorePaths must be an array of strings (ignored)")
            }
        }
        if let raw = object["trustedUrls"] {
            if let items = raw as? [Any], items.count <= maxTrustedUrls {
                for item in items {
                    guard let pattern = item as? String, !pattern.isEmpty, pattern.count <= maxPatternLength,
                        let scheme = pattern.split(separator: ":", maxSplits: 1).first,
                        ["http", "https"].contains(scheme.lowercased())
                    else {
                        settings.problems.append(
                            "trustedUrls has an invalid entry (must start with http:// or https://; ignored)")
                        continue
                    }
                    settings.trustedUrls.append(pattern)
                }
            } else {
                settings.problems.append("trustedUrls must be an array of strings (up to \(maxTrustedUrls); ignored)")
            }
        }
        return settings
    }
}
