// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorFoundation",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorFoundation", targets: ["AnchorFoundation"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AnchorFoundation",
            dependencies: []
        ),
        .testTarget(
            name: "AnchorFoundationTests",
            dependencies: ["AnchorFoundation"]
        ),
    ]
)
