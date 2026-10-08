import Foundation
import WebKit

/// 統合テスト用のハーネス(デバッグビルドのみ)。
/// `HYPERBUF_TEST_SCRIPT=<JS ファイル>` のとき、Web コアの起動後にその JS を WebView の中で実行し、
/// 結果を標準出力に `RESULT: …` として出して終了する。scripts/integration-test.sh が使う。
enum TestHarness {
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
