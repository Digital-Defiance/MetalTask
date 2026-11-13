import Charts
import MetalTelemetry
import SwiftUI

struct DeviceActivityChart: View {
    let history: DeviceActivityHistory?

    var body: some View {
        let segments = history?.segments ?? []
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment) { point in
                    if segment.count == 1 {
                        PointMark(
                            x: .value("Seconds from latest sample", point.secondsFromLatest),
                            y: .value("GPU activity (%)", point.percent)
                        )
                        .symbolSize(16)
                    } else {
                        LineMark(
                            x: .value("Seconds from latest sample", point.secondsFromLatest),
                            y: .value("GPU activity (%)", point.percent),
                            series: .value("Segment", index)
                        )
                    }
                }
            }
        }
        .foregroundStyle(Color.accentColor)
        .chartXScale(domain: -DeviceActivityHistory.windowSeconds...0, range: .plotDimension(padding: 4))
        .chartYScale(domain: 0.0...100.0, range: .plotDimension(padding: 3))
        .chartXAxis {
            AxisMarks(values: [-300.0, -240, -180, -120, -60, 0]) { value in
                AxisGridLine()
                AxisTick()
                if let seconds = value.as(Double.self) {
                    AxisValueLabel(anchor: seconds == 0 ? .topTrailing : .topLeading) {
                        if seconds == 0 {
                            Text("Now")
                        } else {
                            Text(Duration.seconds(-seconds).formatted(.units(allowed: [.minutes], width: .narrow)))
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 50, 100]) { value in
                AxisGridLine()
                if let percent = value.as(Double.self) {
                    AxisValueLabel { Text((percent / 100).formatted(.percent)) }
                }
            }
        }
        .overlay {
            if segments.isEmpty {
                Text(history == nil ? "Waiting for activity history…" : "No GPU activity readings available")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("GPU activity over the last five minutes")
        .accessibilityValue(accessibilitySummary(segments))
        .frame(height: 125)
    }

    private func accessibilitySummary(_ segments: [[DeviceActivityHistory.Point]]) -> String {
        let values = segments.flatMap { $0.map(\.percent) }
        guard let minimum = values.min(), let maximum = values.max() else {
            return history == nil ? "Waiting for activity history" : "No readings available"
        }
        let low = (minimum / 100).formatted(.percent.precision(.fractionLength(0...1)))
        let high = (maximum / 100).formatted(.percent.precision(.fractionLength(0...1)))
        return "Observed range \(low) to \(high)"
    }
}
