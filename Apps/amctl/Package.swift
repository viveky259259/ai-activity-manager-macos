// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "amctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "amctl", targets: ["amctl"]),
        .library(name: "AMCTLCore", targets: ["AMCTLCore"]),
    ],
    dependencies: [
        .package(path: "../../Packages/ActivityIPC"),
        .package(path: "../../Packages/ActivityCore"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "amctl",
            dependencies: [
                "AMCTLCore",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "AMCTLCore",
            dependencies: [
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "AMCTLCoreTests",
            dependencies: [
                "AMCTLCore",
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
