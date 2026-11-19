// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import AppKit
import Testing

@testable import HyperBufKit

@MainActor
@Suite struct ClipboardTextTests {
    /// Runs `body` with a pasteboard of our own: the tests never touch the user's clipboard.
    private func withPasteboard(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.yhojo.hyperbuf.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        body(pasteboard)
    }

    @Test func writtenTextIsReadBack() {
        withPasteboard { pasteboard in
            #expect(ClipboardText.write("docs/設計メモ.md", to: pasteboard))
            #expect(ClipboardText.read(from: pasteboard) == "docs/設計メモ.md")
        }
    }

    @Test func readIsNilWithoutText() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            #expect(ClipboardText.read(from: pasteboard) == nil)
            pasteboard.setData(Data([1, 2, 3]), forType: .png)
            #expect(ClipboardText.read(from: pasteboard) == nil)
        }
    }

    @Test func readIsCutToTheLimit() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString(String(repeating: "あ", count: ClipboardText.limit + 5), forType: .string)
            #expect(ClipboardText.read(from: pasteboard)?.count == ClipboardText.limit)
        }
    }

    @Test func writeRefusesEmptyAndTooLongText() {
        withPasteboard { pasteboard in
            #expect(ClipboardText.write("kept", to: pasteboard))
            #expect(!ClipboardText.write("", to: pasteboard))
            #expect(!ClipboardText.write(String(repeating: "x", count: ClipboardText.limit + 1), to: pasteboard))
            #expect(ClipboardText.read(from: pasteboard) == "kept")
        }
    }
}
