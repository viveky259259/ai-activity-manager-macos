// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ActivityWebGateway",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ActivityWebGateway", targets: ["ActivityWebGateway"]),
    ],
    dependencies: [
        .package(path: "../ActivityCore"),
        .package(path: "../ActivityIPC"),
        .package(path: "../ActivityMCP"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "ActivityWebGateway",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityMCP", package: "ActivityMCP"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityWebGatewayTests",
            dependencies: [
                "ActivityWebGateway",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityMCP", package: "ActivityMCP"),
            ]
        ),
    ]
)
