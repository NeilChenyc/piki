// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-markdown",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Markdown",
            targets: ["Markdown"]
        )
    ],
    dependencies: [
        .package(path: "../../build/SourcePackages/checkouts/swift-cmark"),
    ],
    targets: [
        .target(
            name: "Markdown",
            dependencies: [
                "CAtomic",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/Markdown",
            exclude: [
                "CMakeLists.txt"
            ]
        ),
        .target(
            name: "CAtomic",
            path: "Sources/CAtomic"
        ),
    ],
    swiftLanguageModes: [.v5]
)
