// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "activity-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "activity-mcp", targets: ["activity-mcp"]),
    ],
    dependencies: [
        .package(path: "../../Packages/ActivityMCP"),
        .package(path: "../../Packages/ActivityIPC"),
        .package(path: "../../Packages/ActivityCore"),
    ],
    targets: [
        .executableTarget(
            name: "activity-mcp",
            dependencies: [
                .product(name: "ActivityMCP", package: "ActivityMCP"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityCore", package: "ActivityCore"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
