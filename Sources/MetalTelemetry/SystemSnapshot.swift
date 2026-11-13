import Foundation
import Metal

public struct MetalDeviceInfo: Sendable {
    public let name: String
    public let hasUnifiedMemory: Bool
    public let recommendedWorkingSetBytes: UInt64?

    fileprivate init(device: any MTLDevice) {
        name = device.name
        hasUnifiedMemory = device.hasUnifiedMemory
        let workingSetBytes = device.recommendedMaxWorkingSetSize
        recommendedWorkingSetBytes = workingSetBytes > 0 ? workingSetBytes : nil
    }
}

public struct SystemSnapshot: Sendable {
    public let physicalMemoryBytes: UInt64
    public let defaultMetalDevice: MetalDeviceInfo?

    init(physicalMemoryBytes: UInt64, device: (any MTLDevice)?) {
        self.physicalMemoryBytes = physicalMemoryBytes
        defaultMetalDevice = device.map(MetalDeviceInfo.init)
    }

    public static func capture() -> Self {
        Self(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            device: MTLCreateSystemDefaultDevice()
        )
    }
}
