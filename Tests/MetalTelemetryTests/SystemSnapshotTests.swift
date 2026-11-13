import Foundation
import Metal
import Testing
@testable import MetalTelemetry

@Test func missingMetalDevicePreservesPhysicalMemory() {
    let snapshot = SystemSnapshot(physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024, device: nil)

    #expect(snapshot.physicalMemoryBytes == 17_179_869_184)
    #expect(snapshot.defaultMetalDevice == nil)
}

@Test func liveSnapshotMatchesSystemAndMetal() {
    let snapshot = SystemSnapshot.capture()

    #expect(snapshot.physicalMemoryBytes == ProcessInfo.processInfo.physicalMemory)
    if let device = MTLCreateSystemDefaultDevice() {
        let info = snapshot.defaultMetalDevice
        let workingSetBytes = device.recommendedMaxWorkingSetSize

        #expect(info?.name == device.name)
        #expect(info?.hasUnifiedMemory == device.hasUnifiedMemory)
        #expect(info?.recommendedWorkingSetBytes == (workingSetBytes > 0 ? workingSetBytes : nil))
    } else {
        #expect(snapshot.defaultMetalDevice == nil)
    }
}
