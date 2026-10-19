// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

public enum AccessError: Error, Equatable {
    /// 絶対パスでない・NUL や `..` を含む。
    case invalidPath
    case notFound
    case notMarkdown
    /// 画像以外のリソース。
    case unsupportedResource
    case unreadable
    /// 警告パスのため、確認が要る(リソースは、その場で確認できないので、読み込まない)。
    case needsConfirmation
}

/// Web コアに許すファイルアクセス。パスはすべて絶対パス(docs/file-access.md)。
///
///  - `.md` と画像(拡張子で限る)だけを読む
///  - シンボリックリンクは解決したうえで判定する
///  - 判定(許可 / 警告)は `PathPolicy`。利用者が打った・選んだパス、判定済みの外部要求、復元されたセッションは、
///    判定せずに読む(`readMarkdown`)。リソース(画像)は、読み込みのたびに、ここで必ず判定する
public struct FileAccess: Sendable {
    public let policy: PathPolicy
    public let remembered: RememberedPaths
    /// 読んだ版の識別情報(エディタ連携で、古い表示を見つけるのに使う)。
    public let fingerprints: FileFingerprints

    public init(policy: PathPolicy, remembered: RememberedPaths, fingerprints: FileFingerprints = FileFingerprints()) {
        self.policy = policy
        self.remembered = remembered
        self.fingerprints = fingerprints
    }

    public var home: String { policy.home }

    /// 絶対パスを、`realpath` の形にする(存在するものだけ)。
    public func canonical(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw AccessError.invalidPath
        }
        guard let real = PathUtil.canonicalPath(path) else { throw AccessError.notFound }
        return real
    }

    /// 判定する(存在しないパスは、`notFound`)。
    public func decide(_ path: String) throws -> PathPolicy.Decision {
        policy.decide(try canonical(path), remembered: remembered)
    }

    /// Markdown を読む。**判定はしない**(利用者の意思、判定済みの外部要求、復元)。
    public func readMarkdown(_ path: String) throws -> String {
        guard path.hasSuffix(".md") else { throw AccessError.notMarkdown }
        let real = try canonical(path)
        guard real.hasSuffix(".md") else { throw AccessError.notMarkdown }  // リンク先の実体も `.md` に限る
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: real)) else { throw AccessError.unreadable }
        fingerprints.record(path: real, data: data)
        return String(decoding: data, as: UTF8.self)
    }

    /// 文書から参照される画像。**判定する**(警告パスなら、読み込まない)。
    public func readResource(_ path: String) throws -> (data: Data, mime: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard MimeType.imageExtensions.contains(ext) else { throw AccessError.unsupportedResource }
        let real = try canonical(path)
        guard policy.decide(real, remembered: remembered) == .allow else { throw AccessError.needsConfirmation }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: real), options: .mappedIfSafe) else {
            throw AccessError.unreadable
        }
        return (data, MimeType.forExtension(ext))
    }
}
