import Darwin
import MetalTelemetry
import ModelInspection
import SwiftUI

@main
enum MetalTaskEntryPoint {
    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments {
        case _ where arguments.first == "--snapshot-json":
            await SnapshotCommand.capture(arguments.dropFirst())
        case _ where arguments.first == "--compare":
            SnapshotCommand.compare(arguments.dropFirst())
        case ["--check-lm-studio"]:
            do {
                let instances = try await LMStudioClient().loadedInstances()
                print("LM Studio loaded instances: \(instances.count)")
            } catch {
                FileHandle.standardError.write(Data("LM Studio check failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        case ["--sample-gpu"]:
            switch DeviceActivitySample.capture().reading {
            case let .percent(value):
                print("Device Utilization %: \(value)")
            case let .unavailable(reason):
                print("GPU activity unavailable: \(reason)")
            }
        case ["--sample-process-gpu"]:
            var sampler = ProcessGPUActivitySampler()
            _ = sampler.capture()
            try? await Task.sleep(for: .seconds(1))
            if let sample = sampler.capture() {
                print("PID\tGPU ms/s\tCoverage\tProcess")
                for row in sample.processes.sorted(by: { $0.process.pid < $1.process.pid }) {
                    let rate = row.gpuMillisecondsPerSecond?.formatted(.number.precision(.fractionLength(1))) ?? "—"
                    print("\(row.process.pid)\t\(rate)\t\(row.partial ? "partial" : "observed")\t\(row.name)")
                }
                if sample.partial { print("Some GPU clients could not be attributed.") }
            } else {
                print("Process GPU activity unavailable")
            }
        case _ where arguments.first == "--sample-graphics-footprint":
            guard arguments.count == 2, let pid = Int32(arguments[1]), pid > 0 else {
                print("Usage: MetalTask --sample-graphics-footprint PID")
                return
            }
            if let result = await GraphicsFootprintReader().capture(pid: pid) {
                print(result)
            }
        default:
            MetalTaskApp.main()
        }
    }
}

struct MetalTaskApp: App {
    var body: some Scene {
        Window("MetalTask", id: "main") {
            MetalTaskWindow()
        }
    }
}

private struct MetalTaskWindow: View {
    private let snapshot = SystemSnapshot.capture()
    @State private var live: TelemetryCollector.LiveSample?
    @State private var showsLoadedModels = false

    private var telemetry: TelemetrySnapshot? { live?.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("System") {
                    LabeledContent("Physical memory", value: formattedBytes(snapshot.physicalMemoryBytes))
                }

                Section("Default Metal device") {
                    if let device = snapshot.defaultMetalDevice {
                        LabeledContent("GPU", value: device.name)
                        LabeledContent("Unified memory", value: device.hasUnifiedMemory ? "Yes" : "No")
                        LabeledContent("Recommended working set") {
                            if let bytes = device.recommendedWorkingSetBytes {
                                Text(formattedBytes(bytes))
                            } else {
                                Text("Unavailable")
                            }
                        }
                    } else {
                        Text("No Metal device available")
                    }
                }

                Section("GPU activity") {
                    LabeledContent("Device activity", value: displayValue)
                    DeviceActivityChart(history: live?.deviceHistory)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            ProcessActivityTable(
                sample: telemetry?.processes, hasSample: telemetry != nil,
                footprints: Dictionary(uniqueKeysWithValues: (telemetry?.footprints ?? []).map { ($0.process, $0) })
            )
        }
        .frame(minWidth: 740, minHeight: 650)
        .toolbar {
            Button("Loaded Models", systemImage: "cube") { showsLoadedModels = true }
        }
        .sheet(isPresented: $showsLoadedModels) {
            LoadedModelsView()
        }
        .task {
            live = nil
            let collector = TelemetryCollector()
            async let footprintPolling: Void = collector.pollFootprints()
            while !Task.isCancelled {
                let sample = await collector.sampleLiveActivity()
                guard !Task.isCancelled else { break }
                live = sample
                do { try await Task.sleep(for: .seconds(1)) }
                catch { break }
            }
            await footprintPolling
        }
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        bytes.formatted(.byteCount(style: .memory))
    }
    private var displayValue: String {
        switch telemetry?.device.reading {
        case let .percent(percent):
            (percent / 100).formatted(.percent.precision(.fractionLength(0...1)))
        case .unavailable(.noMetalDevice):
            "Unavailable · No Metal device"
        case .unavailable(.acceleratorUnavailable):
            "Unavailable · No matching accelerator"
        case .unavailable(.statisticsUnavailable):
            "Unavailable · Driver statistics missing"
        case .unavailable(.invalidUtilization):
            "Unavailable · Invalid driver reading"
        case nil:
            "Waiting for sample…"
        }
    }
}

private struct ProcessActivityTable: View {
    private enum Sort: String, CaseIterable {
        case activity = "GPU activity"
        case footprint = "Graphics footprint"
        case name = "Process name"
        case pid = "PID"
    }

    let sample: ProcessGPUActivitySampler.Sample?
    let hasSample: Bool
    let footprints: [ProcessGPUActivity.Identity: FootprintObservation]
    @State private var query = ""
    @State private var sort: Sort = .activity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filter by process name or PID", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Sort by", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
            }
            .padding([.horizontal, .top])

            Table(rows) {
                TableColumn("Process", value: \.name)
                TableColumn("PID") { Text($0.process.pid.formatted(.number.grouping(.never))) }
                    .width(min: 56, ideal: 70)
                TableColumn("GPU ms/s") { row in
                    Text(row.gpuMillisecondsPerSecond?.formatted(.number.precision(.fractionLength(1)))
                         ?? "—")
                }
                .width(min: 80, ideal: 100)
                TableColumn("Coverage") { row in
                    Text(row.gpuMillisecondsPerSecond == nil ? "Unavailable" :
                         row.partial ? "Partial" : "Observed")
                }
                .width(min: 90, ideal: 110)
                TableColumn("Graphics footprint") { row in
                    Text(footprintLabel(for: row.id))
                        .help("Dirty graphics memory charged to this process by macOS")
                }
                .width(min: 130, ideal: 155)
            }
            .frame(minHeight: 170)

            if let status {
                Text(status)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom])
            }
        }
    }

    private func footprintLabel(for identity: ProcessGPUActivity.Identity) -> String {
        guard let observation = footprints[identity] else { return "Pending" }
        switch observation.value {
        case let .bytes(bytes):
            let value = bytes.formatted(.byteCount(style: .memory))
            return observation.isStale ? "\(value) (stale)" : value
        case .noGraphicsCategory: return "No graphics category"
        case .permissionDenied: return "Permission denied"
        case .processChanged: return "Process exited"
        case .timedOut: return "Timed out"
        case .unsupported: return "Unsupported data"
        case .failed: return "Unavailable"
        }
    }

    private var status: String? {
        guard hasSample else { return "Waiting for process samples…" }
        guard let sample else { return "Process GPU activity unavailable." }
        if sample.partial { return "Some GPU clients could not be attributed." }
        if sample.processes.isEmpty { return "No attributable GPU clients observed." }
        return nil
    }

    private var rows: [ProcessGPUActivity] {
        (sample?.processes ?? [])
            .filter {
                query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    || String($0.process.pid).contains(query)
            }
            .sorted { lhs, rhs in
                switch sort {
                case .activity:
                    let left = lhs.gpuMillisecondsPerSecond ?? -.infinity
                    let right = rhs.gpuMillisecondsPerSecond ?? -.infinity
                    if left != right { return left > right }
                case .footprint:
                    let left = footprints[lhs.id]?.value.byteCount
                    let right = footprints[rhs.id]?.value.byteCount
                    if left != right {
                        guard let left else { return false }
                        guard let right else { return true }
                        return left > right
                    }
                case .name:
                    let order = lhs.name.localizedStandardCompare(rhs.name)
                    if order != .orderedSame { return order == .orderedAscending }
                case .pid:
                    break
                }
                return lhs.process.pid < rhs.process.pid
            }
    }
}
