// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityCore", targets: ["ActivityCore"]),
        .library(name: "ActivityCoreTestSupport", targets: ["ActivityCoreTestSupport"]),
    ],
    targets: [
        .target(
            name: "ActivityCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "ActivityCoreTestSupport",
            dependencies: ["ActivityCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityCoreTests",
            dependencies: ["ActivityCore", "ActivityCoreTestSupport"]
        ),
    ]
)
