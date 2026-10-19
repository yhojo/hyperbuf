// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import Testing

@testable import HyperBufKit

@Suite struct UrlPolicyTests {
    private func store(_ t: TempProject) -> RememberedOrigins {
        RememberedOrigins(url: t.url.appendingPathComponent("state/sites.json"))
    }

    @Test func defaultConfirmsWithTheOrigin() throws {
        let t = try TempProject()
        defer { t.remove() }
        let policy = UrlPolicy()
        #expect(
            policy.decide("https://Example.com/a?b=1#c", remembered: store(t))
                == .confirm(origin: "https://example.com"))
        #expect(
            policy.decide("http://example.com:8080/x", remembered: store(t))
                == .confirm(origin: "http://example.com:8080"))
    }

    @Test func trustedPatternsOpenWithoutConfirmation() throws {
        let t = try TempProject()
        defer { t.remove() }
        let policy = UrlPolicy(trusted: ["https://github.com/*", "http://localhost:*", "https://*.example.org/docs/*"])
        let r = store(t)
        #expect(policy.decide("https://github.com/yhojo/hyperbuf", remembered: r) == .open)
        #expect(policy.decide("http://localhost:8765/index.html", remembered: r) == .open)
        #expect(policy.decide("https://a.b.example.org/docs/x", remembered: r) == .open)
        // Non-matching ones are confirmed (a different host, a different scheme, a different path)
        #expect(policy.decide("https://github.com.evil.example/x", remembered: r) != .open)
        #expect(policy.decide("http://github.com/x", remembered: r) != .open)
        #expect(policy.decide("https://a.example.org/other", remembered: r) != .open)
    }

    @Test func rememberedOriginsOpenAndPersist() throws {
        let t = try TempProject()
        defer { t.remove() }
        let r = store(t)
        let policy = UrlPolicy()
        #expect(r.add(origin: "https://docs.example.com"))
        #expect(policy.decide("https://docs.example.com/any/path", remembered: r) == .open)
        #expect(policy.decide("https://docs.example.com:444/x", remembered: r) != .open)  // Other port: other origin
        #expect(store(t).contains(origin: "https://docs.example.com"))  // Persisted
        #expect(r.remove(origin: "https://docs.example.com"))
        #expect(policy.decide("https://docs.example.com/x", remembered: r) != .open)
        #expect(!r.add(origin: "ftp://x"))
    }

    @Test func dangerousUrlsAreDenied() throws {
        let t = try TempProject()
        defer { t.remove() }
        let policy = UrlPolicy(trusted: ["https://*"])  // Rejection takes precedence even with a trusted pattern
        let r = store(t)
        for url in [
            "javascript:alert(1)", "file:///etc/passwd", "ftp://example.com/x", "data:text/html,<b>x</b>",
            "hyperbuf://open?path=/etc/hosts", "https://user:pass@example.com/", "https://user@example.com/",
            "https:///nohost", "https://example.com/\u{0}x", "not a url", String(repeating: "a", count: 3000),
        ] {
            guard case .deny = policy.decide(url, remembered: r) else {
                Issue.record("拒否されるはず: \(url.prefix(40))")
                continue
            }
        }
    }

    @Test func mailtoAlwaysConfirmsAndIsNotRememberable() throws {
        let t = try TempProject()
        defer { t.remove() }
        #expect(UrlPolicy().decide("mailto:someone@example.com", remembered: store(t)) == .confirm(origin: nil))
    }

    @Test func globMatching() {
        #expect(UrlPolicy.glob("https://a/*", matches: "https://a/b"))
        #expect(UrlPolicy.glob("https://a/*", matches: "https://a/"))
        #expect(UrlPolicy.glob("HTTPS://A/*", matches: "https://a/b"))
        #expect(!UrlPolicy.glob("https://a/*", matches: "https://ab/c"))
        #expect(UrlPolicy.glob("*", matches: "anything"))
        #expect(UrlPolicy.glob("https://a/x", matches: "https://a/x"))
        #expect(!UrlPolicy.glob("https://a/x", matches: "https://a/xy"))
        #expect(UrlPolicy.glob("https://*/docs/*.html", matches: "https://h.example/docs/p/q.html"))
        #expect(!UrlPolicy.glob("https://*/docs/*.html", matches: "https://h.example/docs/p/q.htm"))
    }
}
