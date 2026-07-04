// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlazeRadar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "blaze-radar-daemon", targets: ["RadarDaemon"]),
        .executable(name: "blaze", targets: ["BlazeCLI"]),
        .library(name: "RadarCore", targets: ["RadarCore"]),
        .library(name: "RadarClient", targets: ["RadarClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(name: "RadarCore"),
        .target(name: "RadarClient", dependencies: ["RadarCore"]),
        .executableTarget(name: "RadarDaemon", dependencies: ["RadarCore"]),
        .executableTarget(
            name: "BlazeCLI",
            dependencies: [
                "RadarClient",
                "RadarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"]),
    ]
)
