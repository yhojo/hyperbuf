// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyperBufProtocol",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HyperBufProtocol", targets: ["HyperBufProtocol"])
    ],
    targets: [
        // アプリ(サーバー)と hyperbuf CLI(クライアント)が共有する、プロトコルの型と検証。
        .target(name: "HyperBufProtocol"),
        .testTarget(
            name: "HyperBufProtocolTests",
            dependencies: ["HyperBufProtocol"],
            // 適合テスト用の例は、protocol/examples/ を、Swift・CLI・Emacs の全員が共有する。
            exclude: [],
            resources: []
        ),
    ]
)
