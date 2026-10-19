// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
import PackageDescription

let package = Package(
    name: "HyperBuf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyperBuf", targets: ["HyperBuf"])
    ],
    dependencies: [
        // Integration protocol types and validation shared by the app (server) and the CLI (client)
        .package(path: "../../protocol/swift")
    ],
    targets: [
        // Components independent of the OS UI (path validation, protocol, search, etc.). Covered by unit tests.
        .target(
            name: "HyperBufKit",
            dependencies: [.product(name: "HyperBufProtocol", package: "swift")]),
        // SwiftUI + WKWebView shell.
        .executableTarget(
            name: "HyperBuf",
            dependencies: [
                "HyperBufKit",
                .product(name: "HyperBufProtocol", package: "swift"),
                .product(name: "HyperBufIPC", package: "swift"),
            ]),
        .testTarget(name: "HyperBufKitTests", dependencies: ["HyperBufKit"]),
    ]
)
