import Foundation

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

    func remove() { try? FileManager.default.removeItem(at: url) }
}
