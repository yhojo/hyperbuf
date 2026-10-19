// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// The app's appearance. `system` follows the OS setting. `light` / `dark` are fixed regardless of the OS setting.
public enum Appearance: String, Sendable, CaseIterable {
    case system, light, dark
}

/// Opacity of the whole frame (window). Same meaning as Emacs' `(set-frame-parameter nil 'alpha '(80 65))`.
/// Values are percentages (100 is opaque). `active` is for the frontmost (key) frame, `inactive` for the others.
public struct WindowAlpha: Sendable, Equatable {
    public var active: Int
    public var inactive: Int

    public static let opaque = WindowAlpha(active: 100, inactive: 100)
    /// The accepted range for opacity (lower than this and the window becomes invisible).
    public static let range = 10...100

    public init(active: Int, inactive: Int) {
        self.active = active
        self.inactive = inactive
    }

    /// The value for `NSWindow.alphaValue` (0-1). Always opaque when the accessibility "Reduce transparency" is on.
    public func value(isKey: Bool, reduceTransparency: Bool) -> Double {
        reduceTransparency ? 1 : Double(isKey ? active : inactive) / 100
    }
}

/// The scalar and list settings of the config file (`config.json`). docs/user/configuration.md.
/// When adding or removing a settings key, also fix "List of configuration keys" in docs/user/configuration.md (`ConfigDocsTests` checks it).
/// Wrongly typed values stay at their defaults and the reason is left in `problems` (shown as "configuration problems" in `C-h b`).
public struct UserSettings: Sendable, Equatable {
    /// Whether to restore and save the previous state.
    public var restoreSession = true
    /// Whether to turn `\_` inside math back into `_` (compatibility with Marked 2 etc.).
    public var mathUnescapeUnderscore = true
    /// Whether to scroll to the start of the changed part when a file is updated externally.
    public var followUpdates = false
    /// Whether to show the Git branch name in the mode line. docs/dev/buffer-model.md §6.9.
    public var modeLineVcsBranch = true
    /// Appearance (light / dark). Defaults to following the OS.
    public var appearance = Appearance.system
    /// Frame opacity (the default is no transparency).
    public var alpha = WindowAlpha.opaque
    /// Patterns of URLs opened in the browser without confirmation (`*` matches any string).
    public var trustedUrls: [String] = []
    /// Directories that are never a project root (`~/...` or absolute paths; exact match). docs/dev/buffer-model.md §6.4.
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
            // Do not accept a JSON number (1 / 0) as a Boolean (`as? Bool` turns an NSNumber 1 into true)
            if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            settings.problems.append("\(key) must be true or false (ignored)")
            return current
        }
        settings.restoreSession = flag("restoreSession", settings.restoreSession)
        settings.mathUnescapeUnderscore = flag("mathUnescapeUnderscore", settings.mathUnescapeUnderscore)
        settings.followUpdates = flag("followUpdates", settings.followUpdates)
        settings.modeLineVcsBranch = flag("modeLineVcsBranch", settings.modeLineVcsBranch)
        if let raw = object["appearance"] {
            if let name = raw as? String, let value = Appearance(rawValue: name) {
                settings.appearance = value
            } else {
                settings.problems.append("appearance must be \"system\", \"light\" or \"dark\" (ignored)")
            }
        }
        if let raw = object["alpha"] {
            // Two integers (percentages). A JSON Boolean (NSNumber) is not accepted as an integer
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
