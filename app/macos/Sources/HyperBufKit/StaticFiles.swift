import Foundation

/// アプリに同梱した Web コア(`core/dist`)を配る。ルートの内側のファイルだけを返す。
public struct StaticFiles: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = URL(
            fileURLWithPath: Project.canonicalPath(root.path) ?? root.standardizedFileURL.path, isDirectory: true)
    }

    /// 空のパスは `index.html`。
    public func read(_ relative: String) throws -> (data: Data, mime: String) {
        let path = relative.isEmpty ? "index.html" : relative
        guard !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw ProjectError.outside }
        guard let real = Project.canonicalPath(root.appendingPathComponent(path).path) else {
            throw ProjectError.notFound
        }
        guard real.hasPrefix(root.path + "/") else { throw ProjectError.outside }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real, isDirectory: &isDirectory), !isDirectory.boolValue,
            let data = try? Data(contentsOf: URL(fileURLWithPath: real), options: .mappedIfSafe)
        else { throw ProjectError.notFound }
        return (data, MimeType.forExtension((real as NSString).pathExtension))
    }
}
