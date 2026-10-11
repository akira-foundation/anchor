// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorStoredContext",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorStoredContext", targets: ["AnchorStoredContext"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorApplication"),
        .package(path: "../AnchorStorage"),
    ],
    targets: [
        .target(
            name: "AnchorStoredContext",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorApplication", package: "AnchorApplication"),
                .product(name: "AnchorStorage", package: "AnchorStorage"),
            ]
        ),
        .testTarget(
            name: "AnchorStoredContextTests",
            dependencies: [
                "AnchorStoredContext",
                .product(name: "AnchorApplicationTestSupport", package: "AnchorApplication"),
            ]
        ),
    ]
)
