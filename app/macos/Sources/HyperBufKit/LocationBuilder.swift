// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import HyperBufProtocol

/// The "location pointed at" requested by the Web core (`SourceLocation` in `core/src/locate.ts`).
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

/// Adds what only the shell knows (the absolute path, the identity information of the rendered version) to the Web core's location,
/// making the payload handed to the editor.
public enum LocationBuilder {
    public static func build(
        _ web: WebLocation, access: FileAccess, now: Date = Date()
    ) -> Result<LocationPayload, ProtocolError> {
        // Hand only an existing absolute path to the editor
        let absolute: String
        do {
            absolute = try access.canonical(web.path)
        } catch {
            return .failure(ProtocolError(.notFound, "The location of this file cannot be passed to the editor"))
        }
        guard absolute.hasSuffix(".md") else { return .failure(ProtocolError(.notMarkdown, ".md files only")) }
        // Identity information of the version the viewer rendered. Without a record of reading, "the rendered version" is unknown, so it is not passed
        guard let fingerprint = access.fingerprints.get(absolute) else {
            return .failure(ProtocolError(.stale, "No identity information for the rendered version of the file"))
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
