// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorIntelligence",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorIntelligence", targets: ["AnchorIntelligence"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain")
    ],
    targets: [
        .target(
            name: "AnchorIntelligence",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain")
            ]
        ),
        .testTarget(
            name: "AnchorIntelligenceTests",
            dependencies: ["AnchorIntelligence"]
        ),
    ]
)
