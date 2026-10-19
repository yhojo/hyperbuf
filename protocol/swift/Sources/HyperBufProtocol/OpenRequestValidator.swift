// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// A syntactically valid `open` request. Whether the file exists and the project scope are judged by the app (it needs
/// the file system).
public struct ValidatedOpen: Sendable, Equatable {
    public let path: String
    public let line: Int?
    public let anchor: String?
}

/// Input validation for `open` requests. The URL route and the socket route use the same rules
/// (docs/dev/integration-protocol.md §4.2, §3.6).
public enum OpenRequestValidator {
    public static func validate(
        path: String?, line: Int?, anchor: String?, version: Int?
    ) -> Result<ValidatedOpen, ProtocolError> {
        if let version, version != HyperBufProtocol.version {
            return .failure(ProtocolError(.unsupportedVersion, "Unsupported version (v=\(version))"))
        }
        guard let path, path.hasPrefix("/"), !path.contains("\0"),
            !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }),
            !path.split(separator: "/").contains("..")
        else { return .failure(ProtocolError(.badRequest, "Invalid path (absolute paths only)")) }
        guard path.hasSuffix(".md") else {
            return .failure(ProtocolError(.notMarkdown, "Only .md files can be opened"))
        }
        if let line, line <= 0 { return .failure(ProtocolError(.badRequest, "Invalid line")) }
        // Length is counted in Unicode code points (same as JSON Schema maxLength; not the number of graphemes)
        if let anchor, anchor.unicodeScalars.count > HyperBufProtocol.maxAnchorLength {
            return .failure(ProtocolError(.badRequest, "anchor is too long"))
        }
        return .success(ValidatedOpen(path: path, line: line, anchor: (anchor?.isEmpty ?? true) ? nil : anchor))
    }
}
