// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorDomain",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorDomain", targets: ["AnchorDomain"])
    ],
    dependencies: [
        .package(path: "../AnchorFoundation")
    ],
    targets: [
        .target(
            name: "AnchorDomain",
            dependencies: [
                .product(name: "AnchorFoundation", package: "AnchorFoundation")
            ]
        ),
        .testTarget(
            name: "AnchorDomainTests",
            dependencies: ["AnchorDomain"]
        )
    ]
)
