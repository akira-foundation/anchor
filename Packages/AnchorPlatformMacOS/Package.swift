// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorPlatformMacOS",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AnchorPlatformMacOS", targets: ["AnchorPlatformMacOS"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorApplication"),
        .package(path: "../AnchorProvider"),
    ],
    targets: [
        .target(
            name: "AnchorPlatformMacOS",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorApplication", package: "AnchorApplication"),
                .product(name: "AnchorProvider", package: "AnchorProvider"),
            ]
        ),
        .testTarget(
            name: "AnchorPlatformMacOSTests",
            dependencies: ["AnchorPlatformMacOS"]
        ),
    ]
)
