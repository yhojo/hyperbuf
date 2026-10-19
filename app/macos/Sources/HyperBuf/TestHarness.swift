// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import Foundation
import WebKit

/// Harness for integration tests (debug builds only).
/// With `HYPERBUF_TEST_SCRIPT=<JS file>`, runs that JS inside the WebView once the Web core has started,
/// prints the result to standard output as `RESULT: ...` and exits. Used by scripts/integration-test.sh.
enum TestHarness {
    /// With `HYPERBUF_TEST_COMMANDS=<directory>`, runs the `N.js` files placed there in order inside the WebView and
    /// writes the result to `N.result` (`RESULT: ...` or `ERROR: ...`). An entry point for shell scripts to drive the page
    /// (selection, running commands, etc.) in automated tests. Debug builds only.
    /// Scripts are held back until `isReady()` is true (the Web core of that frame has started); otherwise a script sent
    /// right after a frame is created can run before `window.__hyperbuf` exists.
    @MainActor
    static func startCommandChannel(
        for webView: WKWebView, slot: Int = 1, isReady: @escaping @MainActor () -> Bool = { true }
    ) {
        #if DEBUG
            guard let base = ProcessInfo.processInfo.environment["HYPERBUF_TEST_COMMANDS"] else { return }
            // Slot 1 uses the given directory. Other frames use `frame<N>` below it (for multi-frame tests)
            let directory = slot == 1 ? base : base + "/frame\(slot)"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            Task { @MainActor [weak webView] in
                while let webView {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard isReady() else { continue }
                    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
                        .filter { $0.hasSuffix(".js") }.sorted()
                    for name in names {
                        let source = directory + "/" + name
                        guard let script = try? String(contentsOfFile: source, encoding: .utf8) else { continue }
                        try? FileManager.default.moveItem(atPath: source, toPath: source + ".running")
                        let output: String
                        do {
                            let value = try await webView.callAsyncJavaScript(
                                script, arguments: [:], in: nil, contentWorld: .page)
                            output = "RESULT: \(value.map { "\($0)" } ?? "nil")"
                        } catch {
                            output = "ERROR: \(error)"
                        }
                        let result = directory + "/" + name.replacingOccurrences(of: ".js", with: ".result")
                        try? output.write(toFile: result, atomically: true, encoding: .utf8)
                    }
                }
            }
        #endif
    }

    @MainActor
    static func attach(to webView: WKWebView, bridge: Bridge, slot: Int = 1) {
        #if DEBUG
            guard slot == 1, let path = ProcessInfo.processInfo.environment["HYPERBUF_TEST_SCRIPT"],
                let script = try? String(contentsOfFile: path, encoding: .utf8)
            else { return }
            bridge.onReady = { [weak webView] in
                bridge.onReady = nil
                webView?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value): print("RESULT: \(value)")
                    case .failure(let error): print("ERROR: \(error)")
                    }
                    fflush(stdout)
                    exit(0)
                }
            }
        #endif
    }
}
