// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetalTask",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetalTelemetry", targets: ["MetalTelemetry"]),
        .executable(name: "MetalTask", targets: ["MetalTask"]),
    ],
    targets: [
        .target(name: "MetalTelemetry"),
        .target(name: "ModelInspection"),
        .executableTarget(name: "MetalTask", dependencies: ["MetalTelemetry", "ModelInspection"]),
        .testTarget(name: "MetalTelemetryTests", dependencies: ["MetalTelemetry"]),
        .testTarget(name: "ModelInspectionTests", dependencies: ["ModelInspection"]),
    ],
    swiftLanguageModes: [.v6]
)
