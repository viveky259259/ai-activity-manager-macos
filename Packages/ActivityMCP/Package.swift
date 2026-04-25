// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityMCP",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityMCP", targets: ["ActivityMCP"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
        .package(path: "../ActivityIPC"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "ActivityMCP",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityMCPTests",
            dependencies: [
                "ActivityMCP",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
