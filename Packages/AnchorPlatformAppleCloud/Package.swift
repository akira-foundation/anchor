// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorPlatformAppleCloud",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorPlatformAppleCloud", targets: ["AnchorPlatformAppleCloud"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorStorage"),
    ],
    targets: [
        .target(
            name: "AnchorPlatformAppleCloud",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorStorage", package: "AnchorStorage"),
            ]
        ),
        .testTarget(
            name: "AnchorPlatformAppleCloudTests",
            dependencies: [
                "AnchorPlatformAppleCloud",
                .product(name: "AnchorStorageTestSupport", package: "AnchorStorage"),
            ]
        ),
    ]
)
