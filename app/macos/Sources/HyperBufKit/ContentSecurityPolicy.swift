// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

/// The CSP attached to the Web core and to the project's images. It upholds local-first (no outbound communication) and
/// sanitizing of untrusted input (Markdown, SVG). docs/history/poc-rendering-results.md §6.
public enum ContentSecurityPolicy {
    /// The app's scheme (served by a WKURLSchemeHandler).
    public static let scheme = "hyperbuf"

    /// For the Web core. External http(s) is not allowed in any directive.
    /// Running WASM (starry-night) needs `wasm-unsafe-eval` and fetching it needs `connect-src` (the app's own scheme only).
    public static let app = [
        "default-src \(scheme):",
        "script-src \(scheme): 'wasm-unsafe-eval'",
        "style-src \(scheme): 'unsafe-inline'",
        "font-src \(scheme):",
        "img-src \(scheme):",
        "connect-src \(scheme):",
    ].joined(separator: "; ")

    /// For the project's images (SVG in particular). Nothing may be run or loaded (scripts inside SVG are disabled too).
    public static let resource = "default-src 'none'; style-src 'unsafe-inline'"
}
