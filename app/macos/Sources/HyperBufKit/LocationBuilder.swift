// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol

/// Web コアが求めた「指した場所」(`core/src/locate.ts` の `SourceLocation`)。
public struct WebLocation: Decodable, Sendable {
    public struct Range: Decodable, Sendable {
        public let start: LocationPayload.Position
        public let end: LocationPayload.Position
    }

    public struct Context: Decodable, Sendable {
        public let before: String
        public let after: String
    }

    public let path: String
    public let range: Range
    public let precision: LocationPayload.Precision
    public let expect: String
    public let expectTruncated: Bool
    public let context: Context
    public let selection: String
    public let version: Int
}

/// Web コアの位置に、シェルだけが知っていること(絶対パス、描画した版のファイルの識別情報)を足して、
/// エディタに渡すペイロードにする。
public enum LocationBuilder {
    public static func build(
        _ web: WebLocation, access: FileAccess, now: Date = Date()
    ) -> Result<LocationPayload, ProtocolError> {
        // 実在する絶対パスだけを、エディタに渡す
        let absolute: String
        do {
            absolute = try access.canonical(web.path)
        } catch {
            return .failure(ProtocolError(.notFound, "このファイルの位置は、エディタに渡せません"))
        }
        guard absolute.hasSuffix(".md") else { return .failure(ProtocolError(.notMarkdown, ".md のみ扱えます")) }
        // ビューアが描画した版の識別情報。読んだ記録がなければ、「描画した版」が分からないので、渡さない
        guard let fingerprint = access.fingerprints.get(absolute) else {
            return .failure(ProtocolError(.stale, "描画した版のファイルの識別情報がありません"))
        }
        return .success(
            LocationPayload(
                path: absolute,
                range: .init(start: web.range.start, end: web.range.end),
                precision: web.precision, expect: web.expect, expectTruncated: web.expectTruncated,
                context: .init(before: web.context.before, after: web.context.after),
                file: .init(sha256: fingerprint.sha256, mtime: fingerprint.mtime, size: fingerprint.size),
                viewer: .init(selection: web.selection, version: web.version, readAt: fingerprint.readAt),
                markedAt: (now.timeIntervalSince1970 * 1000).rounded()))
    }
}
