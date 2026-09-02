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
        .package(path: "../AnchorStorage"),
        .package(path: "../AnchorSync"),
        .package(path: "../AnchorPersistence"),
        .package(path: "../AnchorSearch"),
        .package(path: "../AnchorKnowledge"),
    ],
    targets: [
        .target(
            name: "AnchorPlatformMacOS",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorApplication", package: "AnchorApplication"),
                .product(name: "AnchorProvider", package: "AnchorProvider"),
                .product(name: "AnchorStorage", package: "AnchorStorage"),
                .product(name: "AnchorPersistence", package: "AnchorPersistence"),
                .product(name: "AnchorSync", package: "AnchorSync"),
                .product(name: "AnchorSearch", package: "AnchorSearch"),
                .product(name: "AnchorKnowledge", package: "AnchorKnowledge"),
            ]
        ),
        .testTarget(
            name: "AnchorPlatformMacOSTests",
            dependencies: [
                "AnchorPlatformMacOS",
                .product(name: "AnchorApplicationTestSupport", package: "AnchorApplication"),
                .product(name: "AnchorSync", package: "AnchorSync"),
            ]
        ),
    ]
)
