// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorSharedUI",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorSharedUI", targets: ["AnchorSharedUI"])
    ],
    dependencies: [
        .package(path: "../AnchorFoundation")
    ],
    targets: [
        .target(
            name: "AnchorSharedUI",
            dependencies: [
                .product(name: "AnchorFoundation", package: "AnchorFoundation")
            ]
        ),
        .testTarget(
            name: "AnchorSharedUITests",
            dependencies: ["AnchorSharedUI"]
        )
    ]
)
