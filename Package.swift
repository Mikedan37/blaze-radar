// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlazeRadar",
    platforms: [.macOS(.v15)],
    products: [
        // Primary deliverable — awareness module for AgentDaemon (or any host process)
        .library(name: "RadarCore", targets: ["RadarCore"]),
        // Optional: try radar without the private AgentDaemon stack
        .executable(name: "blaze-radar-demo-daemon", targets: ["RadarDemoDaemon"]),
        .executable(name: "blaze-radar-demo", targets: ["RadarDemoCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.5"),
    ],
    targets: [
        .target(
            name: "RadarCore",
            dependencies: [
                .product(name: "BlazeDB", package: "BlazeDB"),
            ]
        ),
        // Demo glue — NOT the canonical architecture (see README)
        .target(name: "RadarDemoClient", dependencies: ["RadarCore"]),
        .executableTarget(name: "RadarDemoDaemon", dependencies: ["RadarCore"]),
        .executableTarget(
            name: "RadarDemoCLI",
            dependencies: [
                "RadarDemoClient",
                "RadarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"]),
    ]
)
