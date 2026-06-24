// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PikiApp",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "PikiApp",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "PikiApp",
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "PikiAppTests",
            dependencies: ["PikiApp"],
            path: "Tests/PikiAppTests"
        ),
    ]
)
