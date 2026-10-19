// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// 「エディタで編集」で指した位置(`get-location` の `result.location`)。
/// 位置だけでなく、エディタが「ビューアが指していた場所と、同じ場所か」を確かめるための情報を持つ。
/// docs/dev/edit-location.md §5、protocol/schema/location.schema.json。
public struct LocationPayload: Sendable, Equatable, Codable {
    public struct Position: Sendable, Equatable, Codable {
        /// 1 始まり。
        public var line: Int
        /// 1 始まり。Unicode のコードポイント(Emacs の文字)で数える。
        public var column: Int

        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
    }

    public struct Range: Sendable, Equatable, Codable {
        public var start: Position
        /// その位置の文字を含まない。
        public var end: Position

        public init(start: Position, end: Position) {
            self.start = start
            self.end = end
        }
    }

    public enum Precision: String, Sendable, Codable {
        case exact
        /// 位置が曖昧で、ブロック全体しか確実でない。
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

    /// ビューアが描画した版のファイルの識別情報。エディタは、いまのファイルと比べて、古い表示を見つける。
    public struct File: Sendable, Equatable, Codable {
        public var sha256: String
        /// エポックからのミリ秒。
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
        /// ビューアが、そのファイルを読んだ時刻(エポックからのミリ秒)。
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
    /// 「エディタで編集」を選んだ時刻(エポックからのミリ秒)。
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

    /// 応答の `result` に入れる JSON の値。
    public var json: JSONValue {
        guard let data = try? JSONEncoder().encode(self),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .null }
        return value
    }
}
