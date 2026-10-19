// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Where the session (the sequence of frames; docs/dev/buffer-model.md §9) is saved. A single file overall.
///
/// Rules:
///  - Only data made by the Web core, with just paths and positions (no document contents), is saved. Its size is limited
///  - The contents are not trusted (the Web core validates them). Here only whether it reads as JSON and the rough shape (slots) are checked
///  - The file is 0600 and its directory 0700 (it is a record of the user's work)
///  - Writes go to a temporary file first, then replace (never show an intermediate state)
public struct SessionStore: Sendable {
    /// Maximum size of the saved data (bytes). Keep the same value as the table in docs/dev/session-restore.md §4.
    public static let maxBytes = 4_000_000
    /// Upper limit on the number of frames (`Cmd-1` ... `Cmd-9`). Keep the same value as the table in docs/dev/session-restore.md §4.
    public static let maxFrames = 9

    public static func standardDirectory() -> URL {
        #if DEBUG
            // For tests: only debug builds can swap this, so the user's real session is not used
            if let path = ProcessInfo.processInfo.environment["HYPERBUF_SESSION_DIR"] {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/HyperBuf", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = SessionStore.standardDirectory()) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent("session.json") }

    /// The saved session: `{"version": 2, "active": 1, "frames": [{"slot": 1, "rect": {...}, "snapshot": {...}}]}`.
    /// nil if absent, broken or too large. Frames with an invalid or duplicate slot are dropped.
    public func load() -> [String: Any]? {
        guard let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= Self.maxBytes,
            let data = try? Data(contentsOf: fileURL),
            var stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            stored["version"] as? Int == 2,
            let raw = stored["frames"] as? [[String: Any]]
        else { return nil }
        var seen = Set<Int>()
        var frames: [[String: Any]] = []
        for frame in raw {
            guard let slot = frame["slot"] as? Int, (1...Self.maxFrames).contains(slot), seen.insert(slot).inserted
            else { continue }
            frames.append(frame)
        }
        stored["frames"] = frames
        return stored
    }

    /// Saves the session. Anything too large or not representable as JSON is not saved.
    @discardableResult
    public func save(_ session: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(session),
            let data = try? JSONSerialization.data(withJSONObject: session),
            data.count <= Self.maxBytes
        else { return false }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
        let tmp = directory.appendingPathComponent(".session.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return false }
        guard (try? FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)) != nil else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        chmod(fileURL.path, 0o600)
        return true
    }
}

/// The session-related entries of the config file (`config.json`).
public enum SessionSettings {
    /// `restoreSession`: whether to restore and save the previous state. Defaults to true (disabled only when `false`).
    public static func restoreEnabled(from url: URL = EditorConfig.configURL()) -> Bool {
        guard let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let value = object["restoreSession"] as? Bool
        else { return true }
        return value
    }
}
