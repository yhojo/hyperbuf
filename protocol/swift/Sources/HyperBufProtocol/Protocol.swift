// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// HyperBuf's integration protocol (docs/dev/integration-protocol.md §3, §4).
public enum HyperBufProtocol {
    /// Protocol version. Assumed when the request omits `v`.
    public static let version = 1
    /// Upper limit of one line (one message).
    public static let maxLineBytes = 1 << 20
    /// Default deadline (milliseconds) when waiting for a user's answer, such as a confirmation for out-of-scope paths.
    public static let defaultTimeoutMs = 30_000
    /// Upper limit of the length of `anchor`.
    public static let maxAnchorLength = 200
    /// The app's URL scheme. Used to launch the app and to "open" from external links.
    public static let urlScheme = "hyperbuf"
}

public enum RequestOperation: String, Sendable, CaseIterable {
    case ping
    case open
    /// Returns the position the user pointed at with "Edit in editor" (with information for verification).
    case getLocation = "get-location"
    /// Returns the current view (which document, and roughly where).
    case getView = "get-view"
}

public enum ErrorCode: String, Sendable, CaseIterable {
    case badRequest = "bad-request"
    case unsupportedVersion = "unsupported-version"
    case unknownOp = "unknown-op"
    case notFound = "not-found"
    case notMarkdown = "not-markdown"
    case outsideProject = "outside-project"
    case timeout
    case stale
    case `internal`
}

public struct ProtocolError: Error, Sendable, Equatable, Codable {
    public let code: String
    public let message: String

    public init(_ code: ErrorCode, _ message: String) {
        self.code = code.rawValue
        self.message = message
    }

    /// A code that arrived from another component (such as the Web core). Unknown codes are normalized to `internal`.
    public init(rawCode: String, message: String) {
        self.code = ErrorCode(rawValue: rawCode) == nil ? ErrorCode.internal.rawValue : rawCode
        self.message = message
    }
}

/// A request. Unknown fields are ignored (backward compatibility).
public struct Request: Sendable, Equatable, Codable {
    public var v: Int?
    public var id: String?
    public var op: String
    public var path: String?
    public var line: Int?
    public var anchor: String?
    public var project: String?
    public var target: String?
    public var timeoutMs: Int?

    public init(
        v: Int? = HyperBufProtocol.version, id: String? = nil, op: RequestOperation, path: String? = nil,
        line: Int? = nil,
        anchor: String? = nil, project: String? = nil, target: String? = nil, timeoutMs: Int? = nil
    ) {
        self.v = v
        self.id = id
        self.op = op.rawValue
        self.path = path
        self.line = line
        self.anchor = anchor
        self.project = project
        self.target = target
        self.timeoutMs = timeoutMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v)
        // id may be a string or a number (normalized to a string)
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(n)
        } else {
            id = nil
        }
        op = try c.decode(String.self, forKey: .op)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        line = try c.decodeIfPresent(Int.self, forKey: .line)
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        target = try c.decodeIfPresent(String.self, forKey: .target)
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs)
    }
}

public struct Response: Sendable, Equatable, Codable {
    public var v: Int
    public var id: String?
    public var ok: Bool
    public var result: JSONValue?
    public var error: ProtocolError?

    public static func success(id: String?, _ result: JSONValue = .null) -> Response {
        Response(v: HyperBufProtocol.version, id: id, ok: true, result: result, error: nil)
    }

    public static func failure(id: String?, _ error: ProtocolError) -> Response {
        Response(v: HyperBufProtocol.version, id: id, ok: false, result: nil, error: error)
    }
}
