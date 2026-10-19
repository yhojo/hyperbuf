// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Places under a warn path that the user approved and may be read (a directory or a file). Persisted.
/// (Formerly "trusted roots". The file location and format are carried over as they are.)
///
/// Rules:
///  - Only what the app itself proposed and the user approved in the minibuffer can be added (the Web side cannot add an arbitrary path)
///  - The file is 0600 and its directory 0700 (they reveal where the user works)
public final class RememberedPaths: @unchecked Sendable {
    public static func standardURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/HyperBuf/trusted-roots.json")
    }

    private struct Stored: Codable {
        var v: Int
        var roots: [String]
    }

    private let url: URL
    private let lock = NSLock()
    private var paths: [String]

    public init(url: URL = RememberedPaths.standardURL()) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            paths = stored.roots
        } else {
            paths = []
        }
    }

    public var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    /// Whether `path` (an absolute path) is inside a remembered place (or is it).
    public func contains(_ path: String) -> Bool {
        let real = PathUtil.canonicalPath(path) ?? path
        return all.contains { PathUtil.isInside(real, PathUtil.canonicalPath($0) ?? $0) }
    }

    /// Adds a place and saves. Nonexistent ones are not added.
    @discardableResult
    public func add(_ path: String) -> Bool {
        guard let real = PathUtil.canonicalPath(path) else { return false }
        lock.lock()
        defer { lock.unlock() }
        if !paths.contains(real) {
            paths.append(real)
            save()
        }
        return true
    }

    /// Revokes a remembered place and saves.
    @discardableResult
    public func remove(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = paths.firstIndex(of: path) else { return false }
        paths.remove(at: index)
        save()
        return true
    }

    private func save() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir.path, 0o700)
        guard let data = try? JSONEncoder().encode(Stored(v: 1, roots: paths)) else { return }
        // Write to a temporary file with 0600, then replace (never show a half-written file)
        let tmp = dir.appendingPathComponent(".trusted-roots.\(UUID().uuidString).tmp")
        if FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            chmod(url.path, 0o600)
        }
    }
}
