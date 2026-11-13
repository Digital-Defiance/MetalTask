import Foundation
import Testing
@testable import MetalTelemetry

@Test(arguments: [0.0, 42.5, 100.0])
func validUtilizationPreservesDriverValue(_ percent: Double) {
    let statistics = ["Device Utilization %": NSNumber(value: percent)]

    #expect(DeviceActivitySample.decodeUtilization(statistics) == .percent(percent))
}

@Test func missingStatisticsOrUtilizationIsUnavailable() {
    #expect(DeviceActivitySample.decodeUtilization(nil) == .unavailable(.statisticsUnavailable))
    #expect(DeviceActivitySample.decodeUtilization(12) == .unavailable(.statisticsUnavailable))
    #expect(
        DeviceActivitySample.decodeUtilization(["Renderer Utilization %": 12])
            == .unavailable(.statisticsUnavailable)
    )
}

@Test func malformedUtilizationIsUnavailable() {
    for value: Any in ["42", true, false, -1, 101, Double.nan, Double.infinity, NSNull()] {
        #expect(
            DeviceActivitySample.decodeUtilization(["Device Utilization %": value])
                == .unavailable(.invalidUtilization),
            "Invalid field: \(value)"
        )
    }
}

@Test func unmatchedRegistryIDDoesNotFallBackToAnotherAccelerator() {
    #expect(DeviceActivitySample.readUtilization(registryID: 0) == .unavailable(.acceleratorUnavailable))
}
