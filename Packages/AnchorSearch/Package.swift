// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorSearch",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorSearch", targets: ["AnchorSearch"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain")
    ],
    targets: [
        .target(
            name: "AnchorSearch",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain")
            ]
        ),
        .testTarget(
            name: "AnchorSearchTests",
            dependencies: ["AnchorSearch"]
        ),
    ]
)
