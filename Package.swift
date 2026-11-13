// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MetalTask",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MetalTask", targets: ["MetalTask"]),
        .library(name: "MetalTelemetry", targets: ["MetalTelemetry"]),
    ],
    targets: [
        .target(name: "MetalTelemetry"),
        .executableTarget(name: "MetalTask", dependencies: ["MetalTelemetry"]),
        .testTarget(name: "MetalTelemetryTests", dependencies: ["MetalTelemetry"]),
    ]
)
