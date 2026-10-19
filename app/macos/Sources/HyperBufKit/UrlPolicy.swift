// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation

/// 文書のリンク(外部の URL)を、ブラウザで開くかの判定(docs/user/configuration.md の `trustedUrls`)。
///
/// 段階的に緩める設計:
///  1. 既定は、確認する(URL 全体をミニバッファに出して、利用者が yes / no / always を選ぶ)
///  2. `trustedUrls` のパターン(`*` は任意の文字列)に合う URL は、確認なしで開く
///  3. 「always」で記憶したサイト(オリジン)は、確認なしで開く
///
/// 常に開かないもの: `http` / `https` / `mailto` 以外のスキーム、ユーザー名・パスワードを含む URL(フィッシングで
/// 使われる形)、長すぎる URL、ホストのない URL。
public struct UrlPolicy: Sendable {
    public enum Decision: Sendable, Equatable {
        case open
        /// 確認が要る。`origin` は、「always」で記憶する単位(`https://example.com`)。記憶できないもの(mailto)は nil。
        case confirm(origin: String?)
        case deny(reason: String)
    }

    public static let maxLength = 2048
    public let trusted: [String]

    public init(trusted: [String] = []) { self.trusted = trusted }

    /// `scheme://host[:port]`(小文字)。`http` / `https` の URL だけ。
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
            // メールクライアントを開く。毎回確認する(記憶しない)
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

    /// `*` だけを、任意の文字列(空を含む)として扱う、大文字小文字を区別しない照合。全体が一致すること。
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

/// 「always」で記憶したサイト(オリジン)。永続化する。保存先は 0600、置き場所のディレクトリは 0700。
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
