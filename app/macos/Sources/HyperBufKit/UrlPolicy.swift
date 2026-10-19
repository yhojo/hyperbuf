// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// Judgment of whether to open a document link (external URL) in the browser (`trustedUrls` in docs/user/configuration.md).
///
/// Designed to be loosened step by step:
///  1. By default, confirm (the whole URL is shown in the minibuffer and the user chooses yes / no / always)
///  2. A URL matching a `trustedUrls` pattern (`*` is any string) is opened without confirmation
///  3. A site (origin) remembered with "always" is opened without confirmation
///
/// Never opened: schemes other than `http` / `https` / `mailto`, URLs containing a user name or password (a form used in phishing),
/// overly long URLs, and URLs without a host.
public struct UrlPolicy: Sendable {
    public enum Decision: Sendable, Equatable {
        case open
        /// Confirmation is needed. `origin` is the unit remembered with "always" (`https://example.com`). nil for what cannot be remembered (mailto).
        case confirm(origin: String?)
        case deny(reason: String)
    }

    public static let maxLength = 2048
    public let trusted: [String]

    public init(trusted: [String] = []) { self.trusted = trusted }

    /// `scheme://host[:port]` (lowercase). Only for `http` / `https` URLs.
    public static func origin(of url: String) -> String? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        if let port = components.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    public func decide(_ raw: String, remembered: RememberedOrigins) -> Decision {
        guard raw.count <= Self.maxLength else { return .deny(reason: "URL is too long") }
        guard !raw.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            return .deny(reason: "URL contains control characters")
        }
        guard let components = URLComponents(string: raw), let scheme = components.scheme?.lowercased() else {
            return .deny(reason: "Cannot parse the URL")
        }
        switch scheme {
        case "mailto":
            // Opens the mail client. Confirm every time (not remembered)
            return .confirm(origin: nil)
        case "http", "https":
            guard let host = components.host, !host.isEmpty else { return .deny(reason: "No host") }
            if components.user != nil || components.password != nil {
                return .deny(reason: "URLs with a user name or password are not opened (a form used for phishing)")
            }
            if trusted.contains(where: { Self.glob($0, matches: raw) }) { return .open }
            guard let origin = Self.origin(of: raw) else { return .deny(reason: "Cannot parse the URL") }
            return remembered.contains(origin: origin) ? .open : .confirm(origin: origin)
        default:
            return .deny(reason: "Links with the \(scheme): scheme are not opened (only http / https / mailto)")
        }
    }

    /// Case-insensitive matching that treats only `*` as any string (including empty). The whole string must match.
    public static func glob(_ pattern: String, matches text: String) -> Bool {
        let parts = pattern.lowercased().components(separatedBy: "*")
        let text = text.lowercased()
        guard let first = parts.first, text.hasPrefix(first) else { return false }
        if parts.count == 1 { return text == first }
        var position = text.index(text.startIndex, offsetBy: first.count)
        for part in parts.dropFirst().dropLast() {
            guard let found = text.range(of: part, range: position..<text.endIndex) else { return false }
            position = found.upperBound
        }
        let last = parts[parts.count - 1]
        return text[position...].hasSuffix(last)
            && text.count - text.distance(from: text.startIndex, to: position) >= last.count
    }
}

/// Sites (origins) remembered with "always". Persisted. The file is 0600 and its directory 0700.
public final class RememberedOrigins: @unchecked Sendable {
    public static func standardURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/HyperBuf/trusted-sites.json")
    }

    private struct Stored: Codable {
        var v: Int
        var origins: [String]
    }

    private let url: URL
    private let lock = NSLock()
    private var origins: [String]

    public init(url: URL = RememberedOrigins.standardURL()) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            origins = stored.origins
        } else {
            origins = []
        }
    }

    public var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return origins
    }

    public func contains(origin: String) -> Bool { all.contains(origin.lowercased()) }

    @discardableResult
    public func add(origin: String) -> Bool {
        let value = origin.lowercased()
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return false }
        lock.lock()
        defer { lock.unlock() }
        if !origins.contains(value) {
            origins.append(value)
            save()
        }
        return true
    }

    @discardableResult
    public func remove(origin: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = origins.firstIndex(of: origin.lowercased()) else { return false }
        origins.remove(at: index)
        save()
        return true
    }

    private func save() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir.path, 0o700)
        guard let data = try? JSONEncoder().encode(Stored(v: 1, origins: origins)) else { return }
        let tmp = dir.appendingPathComponent(".trusted-sites.\(UUID().uuidString).tmp")
        if FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            chmod(url.path, 0o600)
        }
    }
}
