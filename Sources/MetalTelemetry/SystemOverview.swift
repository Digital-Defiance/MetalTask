import Foundation
import Metal

public struct SystemOverview: Sendable {
    public struct Device: Sendable {
        public let name: String
        public let hasUnifiedMemory: Bool
        public let recommendedWorkingSetBytes: UInt64
    }

    public let physicalMemoryBytes: UInt64
    public let device: Device?

    public static func capture(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) -> Self {
        let deviceInfo = device.map {
            Device(
                name: $0.name,
                hasUnifiedMemory: $0.hasUnifiedMemory,
                recommendedWorkingSetBytes: $0.recommendedMaxWorkingSetSize
            )
        }

        return Self(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            device: deviceInfo
        )
    }
}
