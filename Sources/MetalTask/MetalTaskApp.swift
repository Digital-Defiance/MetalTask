import MetalTelemetry
import SwiftUI

@main
struct MetalTaskApp: App {
    private let snapshot = SystemSnapshot.capture()

    var body: some Scene {
        Window("MetalTask", id: "main") {
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
                    Text("Live sampling is not implemented in this build.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 300)
        }
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        bytes.formatted(.byteCount(style: .memory))
    }
}
