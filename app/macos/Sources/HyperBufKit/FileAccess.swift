import Foundation

/// Web コアに許すファイルアクセス。相対パスはプロジェクト内、絶対パスは「信頼するルート」の内側だけ。
public struct FileAccess: Sendable {
    public let project: Project
    public let trusted: TrustedRoots
    /// 読んだ版の識別情報(エディタ連携で、古い表示を見つけるのに使う)。
    public let fingerprints: FileFingerprints

    public init(project: Project, trusted: TrustedRoots, fingerprints: FileFingerprints = FileFingerprints()) {
        self.project = project
        self.trusted = trusted
        self.fingerprints = fingerprints
    }

    /// 相対パス(プロジェクト内)または絶対パス(信頼するルートの内側)を、`realpath` の形の絶対パスにする。
    public func absolutePath(_ path: String) throws -> String {
        try resolve(path).path
    }

    /// 絶対パスは、信頼するルートの内側であること。それ以外は、プロジェクト内の相対パス。
    private func resolve(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else { return try project.resolve(path) }
        guard !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw ProjectError.outside }
        guard let real = Project.canonicalPath(path) else { throw ProjectError.notFound }
        guard trusted.contains(real) else { throw ProjectError.outside }
        return URL(fileURLWithPath: real)
    }

    public func readMarkdown(_ path: String) throws -> String {
        guard path.hasSuffix(".md") else { throw ProjectError.notMarkdown }
        // resolve の失敗(範囲外など)を、try? で「読めない」に潰さない
        let file = try resolve(path)
        guard let data = try? Data(contentsOf: file) else { throw ProjectError.unreadable }
        fingerprints.record(path: file.path, data: data)
        return String(decoding: data, as: UTF8.self)
    }

    public func readResource(_ path: String) throws -> (data: Data, mime: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard MimeType.imageExtensions.contains(ext) else { throw ProjectError.unsupportedResource }
        let file = try resolve(path)
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { throw ProjectError.unreadable }
        return (data, MimeType.forExtension(ext))
    }
}
