import Foundation

public struct SnapshotComparison: Sendable {
    public enum Error: Swift.Error {
        case unsupportedVersion
        case differentBootSessions
        case invalidSnapshots
    }

    public enum Presence: String, Sendable {
        case observedInBoth
        case firstObserved
        case noLongerObserved
    }

    public struct ByteChange: Sendable {
        public let increased: Bool
        public let magnitude: UInt64
    }

    public struct ProcessChange: Sendable {
        public let identity: ProcessGPUActivity.Identity
        public let name: String
        public let presence: Presence
        public let gpuMillisecondsPerSecondDelta: Double?
        public let graphicsFootprintChange: ByteChange?
    }

    public let devicePercentagePointDelta: Double?
    /// Nil if either capture could not enumerate processes on the same device.
    public let processes: [ProcessChange]?
    public let partialProcessCoverage: Bool

    public init(before: TelemetrySnapshot, after: TelemetrySnapshot) throws {
        guard before.schemaVersion == TelemetrySnapshot.currentVersion,
              after.schemaVersion == TelemetrySnapshot.currentVersion else {
            throw Error.unsupportedVersion
        }
        guard let session = before.bootSessionID, after.bootSessionID == session else {
            throw Error.differentBootSessions
        }
        guard before.capturedAt <= after.capturedAt else { throw Error.invalidSnapshots }
        let sameDevice = before.device.registryID != nil && before.device.registryID == after.device.registryID
        if sameDevice, case let .percent(old) = before.device.reading,
           case let .percent(new) = after.device.reading,
           (0...100).contains(old), (0...100).contains(new) {
            devicePercentagePointDelta = new - old
        } else {
            devicePercentagePointDelta = nil
        }
        guard sameDevice, let oldSample = before.processes, let newSample = after.processes else {
            processes = nil
            partialProcessCoverage = true
            return
        }

        let old = try Self.index(oldSample.processes, by: \.id)
        let new = try Self.index(newSample.processes, by: \.id)
        let oldFootprints = try Self.index(before.footprints, by: \.process)
        let newFootprints = try Self.index(after.footprints, by: \.process)
        partialProcessCoverage = oldSample.partial || newSample.partial
        processes = Set(old.keys).union(new.keys).sorted { a, b in
            (a.pid, a.startedSeconds, a.startedMicroseconds) < (b.pid, b.startedSeconds, b.startedMicroseconds)
        }.compactMap { identity in
            let previous = old[identity]
            let current = new[identity]
            guard let row = current ?? previous else { return nil }
            let presence: Presence = previous == nil ? .firstObserved :
                current == nil ? .noLongerObserved : .observedInBoth
            var rateDelta: Double?
            if let previous, let current, !previous.partial, !current.partial,
               let oldRate = previous.gpuMillisecondsPerSecond, oldRate.isFinite, oldRate >= 0,
               let newRate = current.gpuMillisecondsPerSecond, newRate.isFinite, newRate >= 0 {
                rateDelta = newRate - oldRate
            }
            var byteChange: ByteChange?
            if presence == .observedInBoth, let oldObservation = oldFootprints[identity],
               let newObservation = newFootprints[identity], !oldObservation.isStale, !newObservation.isStale,
               let oldBytes = oldObservation.value.byteCount, let newBytes = newObservation.value.byteCount {
                byteChange = ByteChange(
                    increased: newBytes >= oldBytes,
                    magnitude: newBytes >= oldBytes ? newBytes - oldBytes : oldBytes - newBytes
                )
            }
            return ProcessChange(identity: identity, name: row.name, presence: presence,
                                 gpuMillisecondsPerSecondDelta: rateDelta, graphicsFootprintChange: byteChange)
        }
    }

    private static func index<T>(
        _ entries: [T], by key: KeyPath<T, ProcessGPUActivity.Identity>
    ) throws -> [ProcessGPUActivity.Identity: T] {
        var index: [ProcessGPUActivity.Identity: T] = [:]
        for entry in entries {
            guard index.updateValue(entry, forKey: entry[keyPath: key]) == nil else {
                throw Error.invalidSnapshots
            }
        }
        return index
    }
}
