// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PikiApp",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "LocalPackages/swift-markdown"),
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
