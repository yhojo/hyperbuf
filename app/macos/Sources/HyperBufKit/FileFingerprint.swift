import CryptoKit
import Foundation

/// ビューアが読んだ版のファイルの識別情報。エディタは、いまのファイルと比べて、古い表示を見つける(R3)。
public struct FileFingerprint: Sendable, Equatable {
    /// ファイルの内容(バイト列)の SHA-256(16 進)。
    public let sha256: String
    /// 更新日時(エポックからのミリ秒)。
    public let mtime: Double
    public let size: Int
    /// 読んだ時刻(エポックからのミリ秒)。
    public let readAt: Double

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Web コアに渡した(= ビューアが描画した)版の、ファイルの識別情報。パスは、`realpath` の形。
/// Web コアは、読んだ版を描画するので、「最後に読んだ版」が、「いま見えている版」になる。
public final class FileFingerprints: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: FileFingerprint] = [:]

    public init() {}

    public func record(path: String, data: Data, now: Date = Date()) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? now.timeIntervalSince1970
        let fingerprint = FileFingerprint(
            sha256: FileFingerprint.sha256Hex(data), mtime: (mtime * 1000).rounded(), size: data.count,
            readAt: (now.timeIntervalSince1970 * 1000).rounded())
        lock.lock()
        items[path] = fingerprint
        lock.unlock()
    }

    public func get(_ path: String) -> FileFingerprint? {
        lock.lock()
        defer { lock.unlock() }
        return items[path]
    }
}
