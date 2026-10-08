// hyperbuf コマンド。M4 で、ソケット経由で HyperBuf.app に「開く」を依頼する実装を入れる。
// 仕様: docs/integration-protocol.md
let version = "0.0.0"

if CommandLine.arguments.contains("--version") {
    print("hyperbuf \(version)")
} else {
    print("usage: hyperbuf [--version] <file>[:<line>]")
}
