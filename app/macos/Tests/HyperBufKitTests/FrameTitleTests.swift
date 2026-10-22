// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Testing

@testable import HyperBufKit

@Suite struct FrameTitleTests {
    private let home = "/Users/me"

    private func title(_ path: String?, root: String? = nil, _ format: FrameTitleFormat = .default) -> String {
        FrameTitle.title(path: path, root: root, home: home, format: format)
    }

    @Test func insideAProjectTheDirectoryIsRelativeToTheRootName() {
        let root = "/Users/me/work/hyperbuf"
        #expect(title("/Users/me/work/hyperbuf/docs/user/README.md", root: root) == "README.md — hyperbuf/docs/user")
        #expect(title("/Users/me/work/hyperbuf/README.md", root: root) == "README.md — hyperbuf")
    }

    @Test func outsideAProjectTheHomeBecomesATilde() {
        #expect(title("/Users/me/Documents/notes/a.md") == "a.md — ~/Documents/notes")
        #expect(title("/Users/me/a.md") == "a.md — ~")
        #expect(title("/usr/local/share/b.md") == "b.md — /usr/local/share")
        #expect(title("/b.md") == "b.md — /")
    }

    @Test func aRootOutsideThePathIsIgnored() {
        #expect(title("/Users/me/x/a.md", root: "/Users/me/other") == "a.md — ~/x")
        #expect(title("/Users/me2/a.md", root: nil) == "a.md — /Users/me2")
    }

    @Test func deepDirectoriesAreCutFromTheFront() {
        let root = "/Users/me/work/hyperbuf"
        #expect(
            title("/Users/me/work/hyperbuf/a/b/c/d/e.md", root: root) == "e.md — …/b/c/d")
        #expect(title("/Users/me/work/hyperbuf/a/b/c/e.md", root: root) == "e.md — hyperbuf/a/b/c")
        #expect(title("/a/b/c/d/e/f.md") == "f.md — …/c/d/e")
    }

    @Test func noBufferOrSimpleFormatGivesTheAppName() {
        #expect(title(nil) == "HyperBuf")
        #expect(title("/Users/me/a.md", .simple) == "HyperBuf")
        #expect(title("relative.md") == "HyperBuf")
    }

    @Test func filenameFormatShowsOnlyTheName() {
        #expect(title("/Users/me/work/hyperbuf/README.md", root: "/Users/me/work/hyperbuf", .filename) == "README.md")
    }
}
