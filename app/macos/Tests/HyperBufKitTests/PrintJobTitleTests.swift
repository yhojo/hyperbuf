// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Testing

@testable import HyperBufKit

@Suite struct PrintJobTitleTests {
    @Test func aBufferNameIsKeptAsItIs() {
        #expect(PrintJobTitle.make("README") == "README")
        #expect(PrintJobTitle.make("設計 メモ.v2") == "設計 メモ.v2")
    }

    @Test func pathSeparatorsAndControlCharactersAreReplaced() {
        #expect(PrintJobTitle.make("search: a/b") == "search- a-b")
        #expect(PrintJobTitle.make("../../etc/passwd") == "-..-etc-passwd")
        #expect(PrintJobTitle.make("a\nb\u{0}c") == "a b c")
    }

    @Test func aLeadingDotIsDroppedSoTheFileIsNotHidden() {
        #expect(PrintJobTitle.make(".hidden") == "hidden")
    }

    @Test func nothingUsableFallsBackToTheAppName() {
        #expect(PrintJobTitle.make(nil) == "HyperBuf")
        #expect(PrintJobTitle.make("") == "HyperBuf")
        #expect(PrintJobTitle.make("  ..  ") == "HyperBuf")
    }

    @Test func aLongNameIsCut() {
        #expect(PrintJobTitle.make(String(repeating: "あ", count: 300)).count == PrintJobTitle.maxLength)
    }
}
