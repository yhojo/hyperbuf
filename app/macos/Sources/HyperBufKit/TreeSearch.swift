// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

public struct SearchHit: Sendable, Equatable, Codable {
    /// 絶対パス。
    public let path: String
    public let line: Int
    public let text: String
}

public struct SearchResponse: Sendable, Equatable, Codable {
    public let results: [SearchHit]
    /// 打ち切りの前の、該当した行の数(1 ファイルにつき最大 `maxPerFile` 行)。
    public let total: Int
    public let truncated: Bool
    /// 検索しなかった理由(起点が `~` や `/` のとき、など)。
    public let refused: String?
    public let listMs: Double
    public let scanMs: Double
}

/// ディレクトリ以下の全文検索(自前の並列走査)。docs/history/poc-navigation-results.md。
///
/// 大文字小文字は ASCII だけ区別しない(日本語などは完全一致)。正規表現は未対応。
/// 正規表現・除外規則が必要になったら、`host.search` の契約を保ったままエンジンを差し替える。
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

    /// 1 ファイルの走査。行ごとに部分一致を探し、最初の `maxPerFile` 行を返す。
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

/// 各 index に 1 スレッドしか書かない前提で、配列への並行な書き込みを許す。
private struct UnsafeSendableBuffer: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<[SearchHit]>
    init(_ buffer: UnsafeMutableBufferPointer<[SearchHit]>) { self.buffer = buffer }
    func set(_ index: Int, _ value: [SearchHit]) { buffer[index] = value }
}
