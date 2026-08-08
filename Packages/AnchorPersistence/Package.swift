// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "AnchorPersistence",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "AnchorPersistence", targets: ["AnchorPersistence"]),
        .library(name: "AnchorPersistenceTestSupport", targets: ["AnchorPersistenceTestSupport"]),
    ],
    dependencies: [
        .package(path: "../AnchorDomain")
    ],
    targets: [
        .target(
            name: "AnchorPersistence",
            dependencies: [
                .product(name: "AnchorDomain", package: "AnchorDomain")
            ]
        ),
        .target(
            name: "AnchorPersistenceTestSupport",
            dependencies: [
                "AnchorPersistence",
                .product(name: "AnchorDomain", package: "AnchorDomain"),
            ]
        ),
        .testTarget(
            name: "AnchorPersistenceTests",
            dependencies: ["AnchorPersistence", "AnchorPersistenceTestSupport"]
        ),
    ]
)
