// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorApplication",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorApplication", targets: ["AnchorApplication"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain"),
        .package(path: "../AnchorProvider"),
    ],
    targets: [
        .target(
            name: "AnchorApplication",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain"),
                .product(name: "AnchorProvider", package: "AnchorProvider"),
            ]
        ),
        .testTarget(
            name: "AnchorApplicationTests",
            dependencies: ["AnchorApplication"]
        ),
    ]
)
