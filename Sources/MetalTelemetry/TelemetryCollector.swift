import Darwin
import Foundation

public struct TelemetrySnapshot: Codable, Sendable {
    public static let currentVersion = 1
    public let schemaVersion: Int
    public let bootSessionID: UUID?
    public let capturedAt: Date
    public let device: DeviceActivitySample
    public let processes: ProcessGPUActivitySampler.Sample?
    public let footprints: [FootprintObservation]
}

public struct FootprintObservation: Codable, Sendable {
    public let process: ProcessGPUActivity.Identity
    public let value: GraphicsFootprint
    public let observedAt: Date
    public let isStale: Bool
}

public actor TelemetryCollector {
    public struct LiveSample: Sendable {
        public let snapshot: TelemetrySnapshot
        public let deviceHistory: DeviceActivityHistory
    }

    private struct TimedFootprint {
        let value: GraphicsFootprint
        let observedAt: Date
        let time: ContinuousClock.Instant

        var nextProbe: ContinuousClock.Instant {
            time + .seconds(value == .permissionDenied ? 60 : 15)
        }
    }

    private static let footprintReader = GraphicsFootprintReader()
    private let bootSessionID = TelemetryCollector.readBootSessionID()
    private var processSampler = ProcessGPUActivitySampler()
    private var deviceHistory = DeviceActivityHistory()
    private var processes: ProcessGPUActivitySampler.Sample?
    private var footprints: [ProcessGPUActivity.Identity: TimedFootprint] = [:]

    public init() {}

    public func sampleLiveActivity() -> LiveSample {
        let snapshot = sampleActivity()
        deviceHistory.append(snapshot.device, at: .now)
        return LiveSample(snapshot: snapshot, deviceHistory: deviceHistory)
    }

    public func sampleActivity() -> TelemetrySnapshot {
        let device = DeviceActivitySample.capture()
        processes = processSampler.capture()
        let identities = Set((processes?.processes ?? []).map(\.id))
        footprints = footprints.filter { identities.contains($0.key) }
        return makeSnapshot(device: device)
    }

    public func pollFootprints() async {
        while !Task.isCancelled {
            _ = await sampleNextFootprint()
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
        }
    }

    /// Captures activity and probes up to four rows, or the specified observed PID.
    public func captureSnapshot(footprintPID: Int32? = nil) async throws -> TelemetrySnapshot {
        _ = sampleActivity()
        try await Task.sleep(for: .seconds(1))
        let activity = sampleActivity()
        var measuredFootprint = false
        for _ in 0..<(footprintPID == nil ? 4 : 1) {
            try Task.checkCancellation()
            guard await sampleNextFootprint(pid: footprintPID) else { break }
            measuredFootprint = true
        }
        try Task.checkCancellation()
        guard measuredFootprint else { return activity }
        _ = sampleActivity()
        try await Task.sleep(for: .seconds(1))
        return sampleActivity()
    }

    private func makeSnapshot(device: DeviceActivitySample) -> TelemetrySnapshot {
        let now = ContinuousClock.now
        let observations = (processes?.processes ?? []).compactMap { row -> FootprintObservation? in
            guard let entry = footprints[row.id] else { return nil }
            return FootprintObservation(
                process: row.id, value: entry.value, observedAt: entry.observedAt,
                isStale: entry.time.duration(to: now) > .seconds(30)
            )
        }
        let orderedProcesses = processes.map {
            ProcessGPUActivitySampler.Sample(
                processes: $0.processes.sorted { $0.process.pid < $1.process.pid },
                partial: $0.partial
            )
        }
        return TelemetrySnapshot(
            schemaVersion: TelemetrySnapshot.currentVersion, bootSessionID: bootSessionID,
            capturedAt: .now, device: device, processes: orderedProcesses,
            footprints: observations.sorted { $0.process.pid < $1.process.pid }
        )
    }

    @discardableResult
    private func sampleNextFootprint(pid: Int32? = nil) async -> Bool {
        let now = ContinuousClock.now
        let due = processes?.processes.filter { row in
            if let pid, row.process.pid != pid { return false }
            guard let entry = footprints[row.id] else { return true }
            return entry.nextProbe <= now
        }.min { left, right in
            let leftTime = footprints[left.id]?.nextProbe ?? now
            let rightTime = footprints[right.id]?.nextProbe ?? now
            if leftTime != rightTime { return leftTime < rightTime }
            let leftRate = left.gpuMillisecondsPerSecond ?? 0
            let rightRate = right.gpuMillisecondsPerSecond ?? 0
            return leftRate == rightRate ? left.process.pid < right.process.pid : leftRate > rightRate
        }
        guard let due, let value = await Self.footprintReader.capture(for: due.id),
              !Task.isCancelled, processes?.processes.contains(where: { $0.id == due.id }) == true else {
            return false
        }
        footprints[due.id] = TimedFootprint(value: value, observedAt: .now, time: .now)
        return true
    }

    private static func readBootSessionID() -> UUID? {
        var bytes = [UInt8](repeating: 0, count: 64)
        var size = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0,
              size > 0, size <= bytes.count else { return nil }
        return UUID(uuidString: String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self))
    }
}
