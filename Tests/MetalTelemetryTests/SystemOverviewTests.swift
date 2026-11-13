import MetalTelemetry
import Testing

@Test func systemMemoryRemainsAvailableWithoutMetal() {
    let overview = SystemOverview.capture(device: nil)

    #expect(overview.device == nil)
    #expect(overview.physicalMemoryBytes > 0)
}
