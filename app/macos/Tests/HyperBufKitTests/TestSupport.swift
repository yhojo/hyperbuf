import Foundation

@testable import HyperBufKit

/// 一時ディレクトリに、テスト用のプロジェクトを作る。
struct TempProject {
    let url: URL

    init(files: [String: String] = [:]) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hyperbuf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (path, text) in files { try write(path, text) }
    }

    func write(_ path: String, _ text: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// `realpath` の形のパス(`/var/...` が `/private/var/...` になる)。判定・比較には、これを使う。
    var real: String { PathUtil.canonicalPath(url.path) ?? url.path }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// 複数のテスト用プロジェクトを、まとめて片づける。
func removeAll(_ projects: TempProject...) {
    for project in projects { project.remove() }
}
