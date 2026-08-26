// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorProvider",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorProvider", targets: ["AnchorProvider"])
    ],
    dependencies: [
        .package(path: "../AnchorDomain")
    ],
    targets: [
        .target(
            name: "AnchorProvider",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain")
            ]
        ),
        .testTarget(
            name: "AnchorProviderTests",
            dependencies: ["AnchorProvider"]
        ),
    ]
)
