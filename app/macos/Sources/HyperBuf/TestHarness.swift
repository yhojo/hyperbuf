import Foundation
import WebKit

/// 統合テスト用のハーネス(デバッグビルドのみ)。
/// `HYPERBUF_TEST_SCRIPT=<JS ファイル>` のとき、Web コアの起動後にその JS を WebView の中で実行し、
/// 結果を標準出力に `RESULT: …` として出して終了する。scripts/integration-test.sh が使う。
enum TestHarness {
    /// `HYPERBUF_TEST_COMMANDS=<ディレクトリ>` のとき、そこに置かれた `N.js` を順に WebView の中で実行して、
    /// 結果を `N.result`(`RESULT: …` または `ERROR: …`)に書く。シェルスクリプトから、ページの操作
    /// (選択、コマンドの実行など)を、自動のテストで行うための入口。デバッグビルドのみ。
    @MainActor
    static func startCommandChannel(for webView: WKWebView) {
        #if DEBUG
            guard let directory = ProcessInfo.processInfo.environment["HYPERBUF_TEST_COMMANDS"] else { return }
            Task { @MainActor [weak webView] in
                while let webView {
                    try? await Task.sleep(for: .milliseconds(100))
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
    static func attach(to webView: WKWebView, bridge: Bridge) {
        #if DEBUG
            guard let path = ProcessInfo.processInfo.environment["HYPERBUF_TEST_SCRIPT"],
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
