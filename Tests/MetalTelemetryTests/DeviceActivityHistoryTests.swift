import Foundation
import Testing
@testable import MetalTelemetry

@Test func deviceHistoryBoundsBothElapsedTimeAndSampleCount() throws {
    var history = DeviceActivityHistory()
    let start = ContinuousClock.now
    let sample = DeviceActivitySample(observedAt: .now, registryID: 1, reading: .percent(20))
    for index in 0...330 {
        history.append(sample, at: start + .milliseconds(index * 500))
    }
    let points = try #require(history.segments.first)
    #expect(points.count == 300)
    #expect(points.first?.secondsFromLatest == -149.5)
    #expect(points.last?.secondsFromLatest == 0)

    history.append(sample, at: start + .seconds(466))
    #expect(history.segments.map(\.count) == [1])
    #expect(history.segments.first?.first?.secondsFromLatest == 0)
}

@Test func deviceHistorySeparatesUnavailableReadingsMissedTicksAndDeviceChanges() {
    var history = DeviceActivityHistory()
    let start = ContinuousClock.now
    func reading(_ reading: DeviceActivitySample.Reading, id: UInt64 = 1) -> DeviceActivitySample {
        DeviceActivitySample(observedAt: .now, registryID: id, reading: reading)
    }
    history.append(reading(.percent(0)), at: start)
    history.append(reading(.percent(25)), at: start + .seconds(1))
    history.append(reading(.unavailable(.statisticsUnavailable)), at: start + .seconds(2))
    history.append(reading(.percent(50)), at: start + .seconds(3))
    history.append(reading(.percent(75)), at: start + .seconds(6))
    history.append(reading(.percent(100), id: 2), at: start + .seconds(7))
    history.append(reading(.unavailable(.statisticsUnavailable)), at: start + .seconds(8))

    #expect(history.segments.map { $0.map(\.percent) } == [[0, 25], [50], [75], [100]])
    #expect(history.segments.map { $0.map(\.secondsFromLatest) } == [[-8, -7], [-5], [-2], [-1]])
}
