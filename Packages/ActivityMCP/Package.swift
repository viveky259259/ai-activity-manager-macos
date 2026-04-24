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
    ],
    targets: [
        .target(
            name: "ActivityMCP",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
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
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
