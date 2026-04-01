// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ForgeDesktopCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ForgeDesktopCore", targets: ["ForgeDesktopCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "ForgeDesktopCore",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources/ForgeDesktopCore"
        ),
        .testTarget(
            name: "ForgeDesktopCoreTests",
            dependencies: ["ForgeDesktopCore"],
            path: "Tests/ForgeDesktopCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
