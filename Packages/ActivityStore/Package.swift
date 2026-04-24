// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityStore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityStore", targets: ["ActivityStore"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "ActivityStore",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityStoreTests",
            dependencies: [
                "ActivityStore",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
            ]
        ),
    ]
)
