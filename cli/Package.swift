// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
import PackageDescription

let package = Package(
    name: "hyperbuf-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        // アプリと共有するプロトコルの型・検証と、ソケットのクライアント
        .package(path: "../protocol/swift")
    ],
    targets: [
        // 引数の解釈・要求の組み立て・アプリへの依頼。単体テストの対象。
        .target(
            name: "HyperBufCLI",
            dependencies: [
                .product(name: "HyperBufProtocol", package: "swift"),
                .product(name: "HyperBufIPC", package: "swift"),
            ]),
        .executableTarget(name: "hyperbuf", dependencies: ["HyperBufCLI"]),
        .testTarget(
            name: "HyperBufCLITests",
            dependencies: [
                "HyperBufCLI",
                .product(name: "HyperBufProtocol", package: "swift"),
                .product(name: "HyperBufIPC", package: "swift"),
            ]),
    ]
)
