// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ForgeDesktopCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ForgeDesktopCore", targets: ["ForgeDesktopCore"]),
    ],
    targets: [
        .target(
            name: "ForgeDesktopCore",
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
