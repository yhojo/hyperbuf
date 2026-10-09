import Foundation

/// 設定ファイル(`config.json`)の `keybindings`: キー列 → コマンド名(`null` は、標準の割り当てを外す)。
/// 例: `{"keybindings": {"M-p": "back", "C-f": null}}`
///
/// ここでは、型・件数・長さだけを検証して、Web コアに渡す。キー表記・コマンド名・衝突の検証と、問題の報告は、
/// Web コア側(`core/src/keybindings.ts`)が行う(`describe-bindings` に出る)。
public enum UserKeybindings {
    public static let maxEntries = 500
    public static let maxLength = 100

    /// Web コアに渡せる形(`null` は `NSNull`)。ファイルがない・不正なら、空。
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
