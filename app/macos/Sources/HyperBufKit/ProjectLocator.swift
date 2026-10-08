import Foundation

/// ファイルが属する「プロジェクト」の決め方(docs/integration-protocol.md §5)。
/// 明示された project → すでに開いているもの → `.git` を含む最寄りの祖先 → ファイルのあるディレクトリ。
public enum ProjectLocator {
    /// 最寄りの、`.git` を含む祖先ディレクトリ。なければ、ファイルのあるディレクトリ。
    public static func root(for file: String) -> String {
        let fm = FileManager.default
        let real = Project.canonicalPath(file) ?? file
        let directory = (real as NSString).deletingLastPathComponent
        var current = directory
        while current != "/" && !current.isEmpty {
            if fm.fileExists(atPath: current + "/.git") { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return directory
    }
}
