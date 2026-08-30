// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorSearch",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorSearch", targets: ["AnchorSearch"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorPersistence"),
    ],
    targets: [
        .target(
            name: "AnchorSearch",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorPersistence", package: "AnchorPersistence"),
            ]
        ),
        .testTarget(
            name: "AnchorSearchTests",
            dependencies: ["AnchorSearch"]
        ),
    ]
)
