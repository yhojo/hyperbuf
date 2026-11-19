// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit

/// Plain-text access to the system clipboard for the Web core (`readClipboard` / `writeClipboard` in core/src/host.ts).
/// It serves the minibuffer's line editing (`C-y`, kills; docs/dev/interaction-model.md §6.3), so only short plain
/// text passes: no other pasteboard types, and a length limit in both directions.
public enum ClipboardText {
    /// Longest text passed in either direction (characters). The minibuffer holds one line.
    public static let limit = 10_000

    /// The pasteboard's plain text, cut to `limit`. nil if it holds no text.
    @MainActor
    public static func read(from pasteboard: NSPasteboard) -> String? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        return String(text.prefix(limit))
    }

    /// Replaces the pasteboard's contents with `text`. Refuses empty text and text longer than `limit`.
    @MainActor
    @discardableResult
    public static func write(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        guard !text.isEmpty, text.count <= limit else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
