import Foundation
import Testing

@testable import HyperBufKit

@Suite struct StaticFilesTests {
    @Test func servesFilesAndIndexByDefault() throws {
        let t = try TempProject(files: ["index.html": "<html/>", "assets/app.js": "1", "assets/x.wasm": "w"])
        defer { t.remove() }
        let files = StaticFiles(root: t.url)
        #expect(try files.read("").mime == "text/html; charset=utf-8")
        #expect(try files.read("assets/app.js").mime == "text/javascript; charset=utf-8")
        #expect(try files.read("assets/x.wasm").mime == "application/wasm")
    }

    @Test func rejectsEscapesAndDirectoriesAndMissing() throws {
        let outside = try TempProject(files: ["secret.txt": "s"])
        let t = try TempProject(files: ["index.html": "", "sub/a.js": ""])
        defer {
            outside.remove()
            t.remove()
        }
        try FileManager.default.createSymbolicLink(
            at: t.url.appendingPathComponent("link.txt"),
            withDestinationURL: outside.url.appendingPathComponent("secret.txt"))
        let files = StaticFiles(root: t.url)
        #expect(throws: AccessError.invalidPath) { try files.read("../secret.txt") }
        #expect(throws: AccessError.invalidPath) { try files.read("link.txt") }
        #expect(throws: AccessError.notFound) { try files.read("sub") }
        #expect(throws: AccessError.notFound) { try files.read("nope.js") }
    }
}

@Suite struct ContentSecurityPolicyTests {
    @Test func appPolicyNeverAllowsExternalOrigins() {
        let csp = ContentSecurityPolicy.app
        #expect(!csp.contains("http"))
        #expect(!csp.contains("*"))
        #expect(!csp.contains("'unsafe-eval'"))
        #expect(csp.contains("'wasm-unsafe-eval'"))
        // script-src に 'unsafe-inline' は許さない(style-src だけ、Markdown の数式・図のために必要)
        let script = csp.split(separator: ";").first { $0.contains("script-src") } ?? ""
        #expect(!script.contains("unsafe-inline"))
    }

    @Test func resourcePolicyAllowsNothing() {
        #expect(ContentSecurityPolicy.resource.hasPrefix("default-src 'none'"))
        #expect(!ContentSecurityPolicy.resource.contains("script-src"))
    }
}
