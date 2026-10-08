// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hyperbuf-cli",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "hyperbuf"),
        .testTarget(name: "hyperbufTests", dependencies: ["hyperbuf"]),
    ]
)
