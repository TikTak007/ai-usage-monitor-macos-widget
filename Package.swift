// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .library(name: "CodexUsageShared", targets: ["CodexUsageShared"]),
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitorApp"]),
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .target(name: "CodexUsageShared"),
        .executableTarget(
            name: "CodexUsageMonitorApp",
            dependencies: ["CodexUsageCore", "CodexUsageShared"]
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore", "CodexUsageShared"]
        ),
    ]
)
