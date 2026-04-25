// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityActions",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityActions", targets: ["ActivityActions"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "ActivityActions",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityActionsTests",
            dependencies: [
                "ActivityActions",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
            ]
        ),
    ]
)
