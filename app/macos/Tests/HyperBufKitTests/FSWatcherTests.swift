import Foundation
import Testing

@testable import HyperBufKit

/// 通知を受け取って、一定時間待つ。FSEvents の通知は、メインキューで届く。
@MainActor
private final class Collector {
    var paths: [String] = []

    func wait(for expected: String, timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if paths.contains(expected) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return paths.contains(expected)
    }
}

@Suite(.serialized) @MainActor struct FSWatcherTests {
    private func makeWatcher(_ t: TempProject, _ c: Collector) -> FSWatcher {
        FSWatcher(root: t.url) { paths in
            MainActor.assumeIsolated { c.paths.append(contentsOf: paths) }
        }
    }

    @Test func reportsModifyCreateAndDelete() async throws {
        let t = try TempProject(files: ["a.md": "one"])
        defer { t.remove() }
        let c = Collector()
        let watcher = makeWatcher(t, c)
        try await Task.sleep(for: .milliseconds(300))  // FSEvents の開始を待つ

        try t.write("a.md", "two")
        #expect(await c.wait(for: "a.md"))

        try t.write("sub/new.md", "x")
        #expect(await c.wait(for: "sub/new.md"))

        try FileManager.default.removeItem(at: t.url.appendingPathComponent("a.md"))
        c.paths.removeAll()
        #expect(await c.wait(for: "a.md"))  // 削除も検知できる(旧ポーリングでは検知できなかった)
        withExtendedLifetime(watcher) {}
    }

    @Test func ignoresNonMarkdownAndExcludedDirectories() async throws {
        let t = try TempProject(files: ["a.md": "one"])
        defer { t.remove() }
        let c = Collector()
        let watcher = makeWatcher(t, c)
        try await Task.sleep(for: .milliseconds(300))

        try t.write("note.txt", "x")
        try t.write("node_modules/pkg/README.md", "x")
        try t.write(".hidden/h.md", "x")
        try t.write("marker.md", "x")  // これだけが届けばよい
        #expect(await c.wait(for: "marker.md"))
        // 監視の開始の直前に作ったファイルの通知が届くことはあるが、除外すべきものは届かない
        #expect(!c.paths.contains("note.txt"))
        #expect(!c.paths.contains { $0.contains("node_modules") || $0.contains(".hidden") })
        withExtendedLifetime(watcher) {}
    }
}
