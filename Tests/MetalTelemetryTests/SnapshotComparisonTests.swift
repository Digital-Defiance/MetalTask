import Foundation
import Testing
@testable import MetalTelemetry

private let boot = UUID()
private let process = ProcessGPUActivity.Identity(pid: 42, startedSeconds: 5, startedMicroseconds: 6)
private let reused = ProcessGPUActivity.Identity(pid: 42, startedSeconds: 6, startedMicroseconds: 0)

private func snapshot(
    time: Double, identity: ProcessGPUActivity.Identity = process, activity: Double = 0,
    bytes: UInt64 = 0, partial: Bool = false, stale: Bool = false, session: UUID? = boot
) -> TelemetrySnapshot {
    let date = Date(timeIntervalSince1970: time)
    return TelemetrySnapshot(
        schemaVersion: 1, bootSessionID: session, capturedAt: date,
        device: .init(observedAt: date, registryID: 123, reading: .percent(activity)),
        processes: .init(processes: [
            .init(process: identity, name: "Workload", gpuMillisecondsPerSecond: activity, partial: partial),
        ], partial: partial),
        footprints: [.init(process: identity, value: .bytes(bytes), observedAt: date, isStale: stale)]
    )
}

@Test func snapshotRoundTripsAndComparesFullWidthBytes() throws {
    let before = snapshot(time: 5, activity: 7, bytes: .max)
    let after = snapshot(time: 7, activity: 10)
    let roundTrip = try JSONDecoder().decode(TelemetrySnapshot.self, from: JSONEncoder().encode(after))
    let change = try SnapshotComparison(before: before, after: roundTrip)
    let row = try #require(change.processes?.first)
    #expect(change.devicePercentagePointDelta == 3)
    #expect(row.presence == .observedInBoth)
    #expect(row.gpuMillisecondsPerSecondDelta == 3)
    #expect(row.graphicsFootprintChange?.magnitude == UInt64.max)
    #expect(row.graphicsFootprintChange?.increased == false)
}

@Test func snapshotComparisonKeepsReusedPIDSeparateAndIgnoresStaleOrPartialReadings() throws {
    let before = snapshot(time: 5, bytes: 10)
    let after = snapshot(time: 7, identity: reused, bytes: 20)
    let change = try SnapshotComparison(before: before, after: after)
    #expect(change.processes?.map(\.presence) == [.noLongerObserved, .firstObserved])
    #expect(change.processes?.allSatisfy { $0.graphicsFootprintChange == nil } == true)

    let partial = snapshot(time: 7, activity: 10, bytes: 20, partial: true, stale: true)
    let result = try SnapshotComparison(before: before, after: partial)
    #expect(result.partialProcessCoverage)
    #expect(result.processes?.first?.graphicsFootprintChange == nil)
    #expect(result.processes?.first?.gpuMillisecondsPerSecondDelta == nil)
}

@Test func snapshotComparisonRejectsOtherBootsAndReversedCaptures() {
    let before = snapshot(time: 5)
    #expect(throws: SnapshotComparison.Error.differentBootSessions) {
        try SnapshotComparison(before: before, after: snapshot(time: 7, session: UUID()))
    }
    #expect(throws: SnapshotComparison.Error.invalidSnapshots) {
        try SnapshotComparison(before: before, after: snapshot(time: 3))
    }
}
