import Foundation
import IOKit
import Metal

/// A single observation of the default Metal device's driver-reported GPU activity.
public struct DeviceActivitySample: Codable, Sendable {
    public enum Reading: Codable, Equatable, Sendable {
        case percent(Double)
        case unavailable(Unavailability)
    }

    public enum Unavailability: String, Codable, Sendable {
        case noMetalDevice
        case acceleratorUnavailable
        case statisticsUnavailable
        case invalidUtilization
    }

    public let observedAt: Date
    public let registryID: UInt64?
    public let reading: Reading

    /// Reads IORegistry synchronously. Periodic callers should sample on a worker.
    public static func capture() -> Self {
        let registryID = MTLCreateSystemDefaultDevice()?.registryID
        let reading = registryID.map(readUtilization) ?? .unavailable(.noMetalDevice)
        return Self(observedAt: .now, registryID: registryID, reading: reading)
    }

    static func readUtilization(registryID: UInt64) -> Reading {
        guard let accelerator = copyAccelerator(registryID: registryID) else {
            return .unavailable(.acceleratorUnavailable)
        }
        defer { IOObjectRelease(accelerator) }

        let statistics = IORegistryEntryCreateCFProperty(
            accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return decodeUtilization(statistics)
    }

    static func decodeUtilization(_ statistics: Any?) -> Reading {
        guard let fields = statistics as? [String: Any],
              let value = fields["Device Utilization %"] else {
            return .unavailable(.statisticsUnavailable)
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else {
            return .unavailable(.invalidUtilization)
        }
        let percent = number.doubleValue
        guard (0...100).contains(percent) else {
            return .unavailable(.invalidUtilization)
        }
        return .percent(percent)
    }
}

// The caller owns the returned service. Require the default device's exact
// registry identity before reading device properties or walking its clients.
func copyAccelerator(registryID: UInt64) -> io_service_t? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
    guard service != IO_OBJECT_NULL else { return nil }
    guard IOObjectConformsTo(service, "IOAccelerator") != 0 else {
        IOObjectRelease(service)
        return nil
    }
    return service
}
