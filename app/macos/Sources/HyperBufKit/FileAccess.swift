// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

public enum AccessError: Error, Equatable {
    /// Not an absolute path, or contains NUL or `..`.
    case invalidPath
    case notFound
    case notMarkdown
    /// A resource other than an image.
    case unsupportedResource
    case unreadable
    /// A warn path, so confirmation is needed (resources cannot be confirmed on the spot, so they are not loaded).
    case needsConfirmation
}

/// The file access granted to the Web core. All paths are absolute (docs/dev/file-access.md).
///
///  - Reads only `.md` and images (limited by extension)
///  - Symbolic links are resolved before judging
///  - The judgment (allow / warn) is `PathPolicy`. Paths the user typed or chose, already-judged external requests and restored sessions
///    are read without judging (`readMarkdown`). Resources (images) are always judged here on every load
public struct FileAccess: Sendable {
    public let policy: PathPolicy
    public let remembered: RememberedPaths
    /// Identity information of the version read (used by the editor integration to detect stale displays).
    public let fingerprints: FileFingerprints

    public init(policy: PathPolicy, remembered: RememberedPaths, fingerprints: FileFingerprints = FileFingerprints()) {
        self.policy = policy
        self.remembered = remembered
        self.fingerprints = fingerprints
    }

    public var home: String { policy.home }

    /// Turns an absolute path into its `realpath` form (existing ones only).
    public func canonical(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw AccessError.invalidPath
        }
        guard let real = PathUtil.canonicalPath(path) else { throw AccessError.notFound }
        return real
    }

    /// Judges (a nonexistent path is `notFound`).
    public func decide(_ path: String) throws -> PathPolicy.Decision {
        policy.decide(try canonical(path), remembered: remembered)
    }

    /// Reads Markdown. **Does not judge** (the user's intent, an already-judged external request, restoration).
    public func readMarkdown(_ path: String) throws -> String {
        guard path.hasSuffix(".md") else { throw AccessError.notMarkdown }
        let real = try canonical(path)
        guard real.hasSuffix(".md") else { throw AccessError.notMarkdown }  // The link target must be `.md` too
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: real)) else { throw AccessError.unreadable }
        fingerprints.record(path: real, data: data)
        return String(decoding: data, as: UTF8.self)
    }

    /// An image referenced from a document. **Judges** (a warn path is not loaded).
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
