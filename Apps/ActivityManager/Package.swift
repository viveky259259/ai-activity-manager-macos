// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ActivityManager",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ActivityManager", targets: ["ActivityManager"]),
        .library(name: "ActivityManagerCore", targets: ["ActivityManagerCore"]),
    ],
    dependencies: [
        .package(path: "../../Packages/ActivityCore"),
        .package(path: "../../Packages/ActivityStore"),
        .package(path: "../../Packages/ActivityActions"),
        .package(path: "../../Packages/ActivityLLM"),
        .package(path: "../../Packages/ActivityIPC"),
        .package(path: "../../Packages/ActivityCapture"),
    ],
    targets: [
        .executableTarget(
            name: "ActivityManager",
            dependencies: [
                "ActivityManagerCore",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityStore", package: "ActivityStore"),
                .product(name: "ActivityActions", package: "ActivityActions"),
                .product(name: "ActivityLLM", package: "ActivityLLM"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityCapture", package: "ActivityCapture"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "ActivityManagerCore",
            dependencies: [
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityStore", package: "ActivityStore"),
                .product(name: "ActivityActions", package: "ActivityActions"),
                .product(name: "ActivityLLM", package: "ActivityLLM"),
                .product(name: "ActivityIPC", package: "ActivityIPC"),
                .product(name: "ActivityCapture", package: "ActivityCapture"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ActivityManagerCoreTests",
            dependencies: [
                "ActivityManagerCore",
                .product(name: "ActivityCore", package: "ActivityCore"),
                .product(name: "ActivityCoreTestSupport", package: "ActivityCore"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
