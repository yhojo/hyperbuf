// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hyperbuf-poc",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "hyperbuf-poc",
            path: "Sources/hyperbuf-poc",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
