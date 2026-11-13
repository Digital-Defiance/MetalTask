/// A rolling history of the device readings for one collector session.
public struct DeviceActivityHistory: Sendable {
    public static let windowSeconds = 300.0
    private static let maximumSamples = 300

    public struct Point: Identifiable, Sendable {
        public let id: ContinuousClock.Instant
        public let secondsFromLatest: Double
        public let percent: Double
    }

    private struct Entry: Sendable {
        let time: ContinuousClock.Instant
        let sample: DeviceActivitySample
    }

    private var entries: [Entry] = []

    mutating func append(_ sample: DeviceActivitySample, at time: ContinuousClock.Instant) {
        let cutoff = time - .seconds(Self.windowSeconds)
        entries.removeAll { $0.time < cutoff }
        if entries.count == Self.maximumSamples {
            entries.removeFirst()
        }
        entries.append(Entry(time: time, sample: sample))
    }

    /// Each segment can be plotted independently so the chart leaves gaps.
    public var segments: [[Point]] {
        guard let latest = entries.last else { return [] }
        var segments: [[Point]] = []
        var previous: Entry?
        for entry in entries {
            guard case let .percent(percent) = entry.sample.reading else {
                previous = nil
                continue
            }
            if previous.map({
                $0.sample.registryID != entry.sample.registryID || $0.time.duration(to: entry.time) > .seconds(2.5)
            }) ?? true {
                segments.append([])
            }
            let offset = latest.time.duration(to: entry.time).components
            segments[segments.count - 1].append(Point(
                id: entry.time,
                secondsFromLatest: Double(offset.seconds) + Double(offset.attoseconds) / 1e18,
                percent: percent
            ))
            previous = entry
        }
        return segments
    }
}
