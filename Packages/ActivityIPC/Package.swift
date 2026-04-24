// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityIPC",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityIPC", targets: ["ActivityIPC"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
    ],
    targets: [
        .target(
            name: "ActivityIPC",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityIPCTests",
            dependencies: [
                "ActivityIPC",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
            ]
        ),
    ]
)
