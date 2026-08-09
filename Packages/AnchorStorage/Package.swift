// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorStorage",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorStorage", targets: ["AnchorStorage"]),
        .library(name: "AnchorStorageTestSupport", targets: ["AnchorStorageTestSupport"]),
    ],
    dependencies: [
        .package(path: "../AnchorDomain")
    ],
    targets: [
        .target(
            name: "AnchorStorage",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain")
            ]
        ),
        .target(
            name: "AnchorStorageTestSupport",
            dependencies: [
                "AnchorStorage",
                .product(name: "AnchorDomain", package: "AnchorDomain"),
            ]
        ),
        .testTarget(
            name: "AnchorStorageTests",
            dependencies: ["AnchorStorage", "AnchorStorageTestSupport"]
        ),
    ]
)
