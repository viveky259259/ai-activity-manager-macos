// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityLLM",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityLLM", targets: ["ActivityLLM"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
    ],
    targets: [
        .target(
            name: "ActivityLLM",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityLLMTests",
            dependencies: [
                "ActivityLLM",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
            ]
        ),
    ]
)
