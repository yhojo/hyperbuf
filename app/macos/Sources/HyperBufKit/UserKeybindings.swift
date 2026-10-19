// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// `keybindings` in the config file (`config.json`): key sequence -> command name (`null` removes the default binding).
/// Example: `{"keybindings": {"M-p": "back", "C-f": null}}`
///
/// Here only type, count and length are validated before passing to the Web core. Validation of key notation, command names and conflicts,
/// and reporting problems, are done on the Web core side (`core/src/keybindings.ts`) (shown in `describe-bindings`).
public enum UserKeybindings {
    public static let maxEntries = 500
    public static let maxLength = 100

    /// The form that can be passed to the Web core (`null` is `NSNull`). Empty if the file is absent or invalid.
    public static func load(from url: URL = EditorConfig.configURL()) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let raw = object["keybindings"] as? [String: Any],
            raw.count <= maxEntries
        else { return [:] }
        var out: [String: Any] = [:]
        for (sequence, value) in raw where sequence.count <= maxLength {
            if value is NSNull {
                out[sequence] = NSNull()
            } else if let command = value as? String, command.count <= maxLength {
                out[sequence] = command
            }
        }
        return out
    }
}
