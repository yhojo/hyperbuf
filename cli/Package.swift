// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo
import PackageDescription

let package = Package(
    name: "hyperbuf-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Protocol types and validation shared with the app, and the socket client
        .package(path: "../protocol/swift")
    ],
    targets: [
        // Argument parsing, request building and handing requests to the app. Covered by unit tests.
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
