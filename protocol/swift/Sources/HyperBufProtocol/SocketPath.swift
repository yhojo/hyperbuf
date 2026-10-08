import Foundation

/// ソケットの置き場所。`sun_path` は 104 バイト未満でなければならない。
public enum SocketPath {
    public static let maxBytes = 103

    /// `~/Library/Application Support/HyperBuf/hyperbuf.sock`。長すぎるときは、`$TMPDIR` 配下(ユーザーごとに隔離された場所)。
    public static func standard(home: String = NSHomeDirectory(), tmp: String = NSTemporaryDirectory()) -> String {
        let primary = home + "/Library/Application Support/HyperBuf/hyperbuf.sock"
        if primary.utf8.count <= maxBytes { return primary }
        let dir = (tmp as NSString).standardizingPath
        return dir + "/hyperbuf-\(getuid()).sock"
    }
}
