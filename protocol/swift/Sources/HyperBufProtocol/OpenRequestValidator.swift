// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// 構文として正しい `open` 要求。ファイルの存在・プロジェクトの範囲の判定は、アプリ側(ファイルシステムが要る)で行う。
public struct ValidatedOpen: Sendable, Equatable {
    public let path: String
    public let line: Int?
    public let anchor: String?
}

/// `open` 要求の入力検証。URL 経由とソケット経由で、同じ規則を使う(docs/integration-protocol.md §6・§11.6)。
public enum OpenRequestValidator {
    public static func validate(
        path: String?, line: Int?, anchor: String?, version: Int?
    ) -> Result<ValidatedOpen, ProtocolError> {
        if let version, version != HyperBufProtocol.version {
            return .failure(ProtocolError(.unsupportedVersion, "未対応のバージョンです(v=\(version))"))
        }
        guard let path, path.hasPrefix("/"), !path.contains("\0"),
            !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }),
            !path.split(separator: "/").contains("..")
        else { return .failure(ProtocolError(.badRequest, "path が不正です(絶対パスのみ)")) }
        guard path.hasSuffix(".md") else { return .failure(ProtocolError(.notMarkdown, ".md のみ開けます")) }
        if let line, line <= 0 { return .failure(ProtocolError(.badRequest, "line が不正です")) }
        // 長さは Unicode のコードポイントで数える(JSON Schema の maxLength と同じ。書記素の数ではない)
        if let anchor, anchor.unicodeScalars.count > HyperBufProtocol.maxAnchorLength {
            return .failure(ProtocolError(.badRequest, "anchor が長すぎます"))
        }
        return .success(ValidatedOpen(path: path, line: line, anchor: (anchor?.isEmpty ?? true) ? nil : anchor))
    }
}
