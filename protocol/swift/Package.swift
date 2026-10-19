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
        // Protocol types and validation shared by the app (server) and the hyperbuf CLI (client).
        .target(name: "HyperBufProtocol"),
        // Unix domain socket server (app) and client (CLI).
        .target(name: "HyperBufIPC", dependencies: ["HyperBufProtocol"]),
        // The examples for conformance tests (protocol/examples/) are shared by Swift, the CLI and Emacs.
        .testTarget(name: "HyperBufProtocolTests", dependencies: ["HyperBufProtocol"]),
        .testTarget(name: "HyperBufIPCTests", dependencies: ["HyperBufIPC", "HyperBufProtocol"]),
    ]
)
