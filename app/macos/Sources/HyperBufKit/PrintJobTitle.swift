// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// The title of a print job, which the print dialog proposes as the file name when saving as a PDF (`<title>.pdf`).
/// The Web core sends the buffer's name (a file name without its extension, or a virtual buffer's name); it is
/// untrusted text, so it is made safe as a file name here.
public enum PrintJobTitle {
    public static let fallback = "HyperBuf"
    public static let maxLength = 100

    /// `raw` with path separators (`/`, `:`) and control characters replaced, cut to `maxLength` characters.
    /// The fallback when nothing is left.
    public static func make(_ raw: String?) -> String {
        let cleaned = String(
            (raw ?? "").unicodeScalars.map { scalar -> Character in
                if scalar == "/" || scalar == ":" { return "-" }
                return CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
            })
        let trimmed = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        // A leading dot would make the saved file hidden
        let visible = String(trimmed.drop { $0 == "." })
        return visible.isEmpty ? fallback : visible
    }
}
