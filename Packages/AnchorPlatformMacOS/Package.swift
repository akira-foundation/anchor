// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorPlatformMacOS",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AnchorPlatformMacOS", targets: ["AnchorPlatformMacOS"]),
        .library(name: "AnchorMCPServerCore", targets: ["AnchorMCPServerCore"]),
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
        .package(path: "../AnchorIntelligence"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
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
                .product(name: "AnchorIntelligence", package: "AnchorIntelligence"),
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
        .target(
            name: "AnchorMCPServerCore",
            dependencies: [
                "AnchorPlatformMacOS",
                .product(name: "AnchorApplication", package: "AnchorApplication"),
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "AnchorMCPServerCoreTests",
            dependencies: ["AnchorMCPServerCore", .product(name: "MCP", package: "swift-sdk")]
        ),
    ]
)
