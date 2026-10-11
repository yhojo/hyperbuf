// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
import PackageDescription

let package = Package(
    name: "HyperBufProtocol",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HyperBufProtocol", targets: ["HyperBufProtocol"]),
        .library(name: "HyperBufIPC", targets: ["HyperBufIPC"]),
    ],
    targets: [
        // アプリ(サーバー)と hyperbuf CLI(クライアント)が共有する、プロトコルの型と検証。
        .target(name: "HyperBufProtocol"),
        // Unix ドメインソケットのサーバー(アプリ)とクライアント(CLI)。
        .target(name: "HyperBufIPC", dependencies: ["HyperBufProtocol"]),
        // 適合テスト用の例(protocol/examples/)は、Swift・CLI・Emacs の全員が共有する。
        .testTarget(name: "HyperBufProtocolTests", dependencies: ["HyperBufProtocol"]),
        .testTarget(name: "HyperBufIPCTests", dependencies: ["HyperBufIPC", "HyperBufProtocol"]),
    ]
)
