// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// The position pointed at by "Edit in editor" (`result.location` of `get-location`).
/// Besides the position, it carries information for the editor to check "is this the same place the viewer was pointing
/// at?".
/// docs/dev/edit-location.md §5、protocol/schema/location.schema.json。
public struct LocationPayload: Sendable, Equatable, Codable {
    public struct Position: Sendable, Equatable, Codable {
        /// 1-based.
        public var line: Int
        /// 1-based. Counted in Unicode code points (Emacs characters).
        public var column: Int

        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
    }

    public struct Range: Sendable, Equatable, Codable {
        public var start: Position
        /// Does not include the character at that position.
        public var end: Position

        public init(start: Position, end: Position) {
            self.start = start
            self.end = end
        }
    }

    public enum Precision: String, Sendable, Codable {
        case exact
        /// The position is ambiguous; only the whole block is certain.
        case block
    }

    public struct Context: Sendable, Equatable, Codable {
        public var before: String
        public var after: String

        public init(before: String, after: String) {
            self.before = before
            self.after = after
        }
    }

    /// Identification of the file version the viewer rendered. The editor compares it with the current file to detect a
    /// stale view.
    public struct File: Sendable, Equatable, Codable {
        public var sha256: String
        /// Milliseconds since the epoch.
        public var mtime: Double
        public var size: Int

        public init(sha256: String, mtime: Double, size: Int) {
            self.sha256 = sha256
            self.mtime = mtime
            self.size = size
        }
    }

    public struct Viewer: Sendable, Equatable, Codable {
        public var selection: String
        public var version: Int
        /// Time the viewer read that file (milliseconds since the epoch).
        public var readAt: Double

        public init(selection: String, version: Int, readAt: Double) {
            self.selection = selection
            self.version = version
            self.readAt = readAt
        }
    }

    public var v: Int
    public var path: String
    public var range: Range
    public var precision: Precision
    public var expect: String
    public var expectTruncated: Bool
    public var context: Context
    public var file: File
    public var viewer: Viewer
    /// Time "Edit in editor" was chosen (milliseconds since the epoch).
    public var markedAt: Double

    public init(
        path: String, range: Range, precision: Precision, expect: String, expectTruncated: Bool, context: Context,
        file: File, viewer: Viewer, markedAt: Double
    ) {
        self.v = HyperBufProtocol.version
        self.path = path
        self.range = range
        self.precision = precision
        self.expect = expect
        self.expectTruncated = expectTruncated
        self.context = context
        self.file = file
        self.viewer = viewer
        self.markedAt = markedAt
    }

    /// A JSON value to put into the response `result`.
    public var json: JSONValue {
        guard let data = try? JSONEncoder().encode(self),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .null }
        return value
    }
}
