/// Web コアと、プロジェクトの画像に付ける CSP。local first(外部への通信を許さない)と、
/// 不信任の入力(Markdown・SVG)の無害化が、ここで守られる。docs/poc-rendering-results.md §6。
public enum ContentSecurityPolicy {
    /// アプリのスキーム(WKURLSchemeHandler で配る)。
    public static let scheme = "hyperbuf"

    /// Web コア用。外部の http(s) は、どのディレクティブでも許さない。
    /// WASM(starry-night)の実行に `wasm-unsafe-eval`、その取得に `connect-src` が要る(自アプリのスキームのみ)。
    public static let app = [
        "default-src \(scheme):",
        "script-src \(scheme): 'wasm-unsafe-eval'",
        "style-src \(scheme): 'unsafe-inline'",
        "font-src \(scheme):",
        "img-src \(scheme):",
        "connect-src \(scheme):",
    ].joined(separator: "; ")

    /// プロジェクトの画像(特に SVG)用。何も実行・読み込みさせない(SVG の中の script も無効)。
    public static let resource = "default-src 'none'; style-src 'unsafe-inline'"
}
