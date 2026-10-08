// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyperBuf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyperBuf", targets: ["HyperBuf"])
    ],
    dependencies: [
        // アプリ(サーバー)と CLI(クライアント)が共有する、連携プロトコルの型と検証
        .package(path: "../../protocol/swift")
    ],
    targets: [
        // OS の UI に依存しない部品(パスの検証、プロトコル、検索など)。単体テストの対象。
        .target(
            name: "HyperBufKit",
            dependencies: [.product(name: "HyperBufProtocol", package: "swift")]),
        // SwiftUI + WKWebView のシェル。
        .executableTarget(name: "HyperBuf", dependencies: ["HyperBufKit"]),
        .testTarget(name: "HyperBufKitTests", dependencies: ["HyperBufKit"]),
    ]
)
