// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityCapture",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityCapture", targets: ["ActivityCapture"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
    ],
    targets: [
        .target(
            name: "ActivityCapture",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityCaptureTests",
            dependencies: [
                "ActivityCapture",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
            ]
        ),
    ]
)
