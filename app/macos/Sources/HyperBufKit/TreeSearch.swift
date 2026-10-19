// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

public struct SearchHit: Sendable, Equatable, Codable {
    /// Absolute path.
    public let path: String
    public let line: Int
    public let text: String
}

public struct SearchResponse: Sendable, Equatable, Codable {
    public let results: [SearchHit]
    /// Number of matching lines before cutoff (at most `maxPerFile` lines per file).
    public let total: Int
    public let truncated: Bool
    /// The reason the search was not run (the base is `~` or `/`, etc.).
    public let refused: String?
    public let listMs: Double
    public let scanMs: Double
}

/// Full-text search below a directory (own parallel traversal). docs/history/poc-navigation-results.md.
///
/// Case is ignored for ASCII only (Japanese etc. must match exactly). Regular expressions are not supported.
/// If regular expressions or exclusion rules become necessary, swap the engine while keeping the `host.search` contract.
public enum TreeSearch {
    public static let maxPerFile = 3

    public static func search(dir: String, home: String, query: String, limit: Int = 200) -> SearchResponse {
        let t0 = DispatchTime.now()
        let tree = DirectoryLister.tree(dir, home: home)
        if let refused = tree.refused {
            return SearchResponse(results: [], total: 0, truncated: false, refused: refused, listMs: 0, scanMs: 0)
        }
        let root = PathUtil.canonicalPath(dir) ?? dir
        let files = tree.files.map { root + "/" + $0 }
        let t1 = DispatchTime.now()
        let needle = Array(query.utf8).map(fold)
        var perFile = [[SearchHit]](repeating: [], count: files.count)
        if !needle.isEmpty {
            perFile.withUnsafeMutableBufferPointer { buffer in
                let out = UnsafeSendableBuffer(buffer)
                DispatchQueue.concurrentPerform(iterations: files.count) { i in
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: files[i]), options: .mappedIfSafe)
                    else { return }
                    out.set(i, scan(data, needle, path: files[i]))
                }
            }
        }
        let all = perFile.flatMap { $0 }
        let t2 = DispatchTime.now()
        return SearchResponse(
            results: Array(all.prefix(max(0, limit))),
            total: all.count,
            truncated: all.count > limit || tree.truncated,
            refused: nil,
            listMs: millis(t0, t1),
            scanMs: millis(t1, t2)
        )
    }

    private static func millis(_ a: DispatchTime, _ b: DispatchTime) -> Double {
        Double(b.uptimeNanoseconds - a.uptimeNanoseconds) / 1e6
    }

    private static func fold(_ b: UInt8) -> UInt8 { (b >= 65 && b <= 90) ? b + 32 : b }

    /// Scans one file. Looks for a substring match per line and returns the first `maxPerFile` lines.
    static func scan(_ data: Data, _ needle: [UInt8], path: String) -> [SearchHit] {
        var found: [SearchHit] = []
        let m = needle.count
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            let n = p.count
            var i = 0
            var line = 1
            while i < n && found.count < maxPerFile {
                var e = i
                while e < n && p[e] != 10 { e += 1 }
                if e - i >= m {
                    var s = i
                    while s + m <= e {
                        var k = 0
                        while k < m && fold(p[s + k]) == needle[k] { k += 1 }
                        if k == m {
                            let text = String(
                                decoding: UnsafeBufferPointer(rebasing: p[i..<min(e, i + 200)]), as: UTF8.self)
                            found.append(SearchHit(path: path, line: line, text: text))
                            break
                        }
                        s += 1
                    }
                }
                i = e + 1
                line += 1
            }
        }
        return found
    }
}

/// Allows concurrent writes to the array, on the premise that each index is written by only one thread.
private struct UnsafeSendableBuffer: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<[SearchHit]>
    init(_ buffer: UnsafeMutableBufferPointer<[SearchHit]>) { self.buffer = buffer }
    func set(_ index: Int, _ value: [SearchHit]) { buffer[index] = value }
}
