import Foundation
import MetalTelemetry
import SwiftUI

@main
struct MetalTaskApp: App {
    private let overview = SystemOverview.capture()

    var body: some Scene {
        Window("MetalTask", id: "overview") {
            Form {
                Section("System") {
                    LabeledContent("Physical memory", value: overview.physicalMemoryBytes.formatted(.byteCount(style: .memory)))
                }

                Section("Metal device") {
                    if let device = overview.device {
                        LabeledContent("Default GPU", value: device.name)
                        LabeledContent("Unified memory", value: device.hasUnifiedMemory ? "Yes" : "No")
                        if device.recommendedWorkingSetBytes > 0 {
                            LabeledContent(
                                "Recommended working set",
                                value: device.recommendedWorkingSetBytes.formatted(.byteCount(style: .memory))
                            )
                            .help("Metal’s guideline for GPU allocations that avoid affecting performance.")
                        }
                    } else {
                        Text("No default Metal device is available.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("GPU activity") {
                    Text("Live GPU activity is unavailable in this build.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 280)
        }
        .defaultSize(width: 560, height: 340)
    }
}
