// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorSync",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorSync", targets: ["AnchorSync"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorApplication")
    ],
    targets: [
        .target(
            name: "AnchorSync",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorApplication", package: "AnchorApplication")
            ]
        ),
        .testTarget(
            name: "AnchorSyncTests",
            dependencies: ["AnchorSync"]
        )
    ]
)
