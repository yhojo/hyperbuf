// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import CryptoKit
import Foundation

/// Identity information of the file version the viewer read. The editor compares it with the current file to detect a stale display (R3).
public struct FileFingerprint: Sendable, Equatable {
    /// SHA-256 (hex) of the file contents (bytes).
    public let sha256: String
    /// Modification time (milliseconds since the epoch).
    public let mtime: Double
    public let size: Int
    /// Time of reading (milliseconds since the epoch).
    public let readAt: Double

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Identity information of the file version handed to the Web core (= rendered by the viewer). The path is in `realpath` form.
/// The Web core renders what it read, so "the last version read" is "the version currently visible".
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
