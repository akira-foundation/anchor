// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorKnowledge",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorKnowledge", targets: ["AnchorKnowledge"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorPersistence"),
    ],
    targets: [
        .target(
            name: "AnchorKnowledge",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorPersistence", package: "AnchorPersistence"),
            ]
        ),
        .testTarget(
            name: "AnchorKnowledgeTests",
            dependencies: ["AnchorKnowledge"]
        ),
    ]
)
