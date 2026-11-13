import Darwin
import Foundation
import MetalTelemetry

enum SnapshotCommand {
    static func capture(_ arguments: ArraySlice<String>) async {
        var footprintPID: Int32?
        if !arguments.isEmpty {
            guard arguments.count == 2, arguments.first == "--footprint-pid",
                  let last = arguments.last, let pid = Int32(last), pid > 0 else {
                fail("Usage: MetalTask --snapshot-json [--footprint-pid PID]")
            }
            footprintPID = pid
        }
        do {
            let snapshot = try await TelemetryCollector().captureSnapshot(footprintPID: footprintPID)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        } catch {
            fail("Could not capture a telemetry snapshot.")
        }
    }

    static func compare(_ arguments: ArraySlice<String>) {
        guard arguments.count == 2 else { fail("Usage: MetalTask --compare BEFORE.json AFTER.json") }
        do {
            let result = try SnapshotComparison(before: read(arguments[arguments.startIndex]),
                                                after: read(arguments[arguments.index(after: arguments.startIndex)]))
            let activity = result.devicePercentagePointDelta.map(signed) ?? "unavailable"
            print("Device activity change (percentage points): \(activity)")
            guard let processes = result.processes else {
                print("Process comparison unavailable.")
                return
            }
            if result.partialProcessCoverage { print("Process coverage was partial.") }
            print("PID\tGPU ms/s change\tGraphics bytes change\tPresence\tProcess")
            for row in processes {
                let activity = row.gpuMillisecondsPerSecondDelta.map(signed) ?? "—"
                let footprint = row.graphicsFootprintChange.map {
                    ($0.magnitude == 0 ? "" : $0.increased ? "+" : "-") + String($0.magnitude)
                } ?? "—"
                let name = row.name.replacingOccurrences(of: "\t", with: " ")
                    .components(separatedBy: .controlCharacters).joined()
                print("\(row.identity.pid)\t\(activity)\t\(footprint)\t\(row.presence.rawValue)\t\(name)")
            }
        } catch SnapshotComparison.Error.differentBootSessions {
            fail("Capture both snapshots on the same Mac during the same boot session.")
        } catch SnapshotComparison.Error.unsupportedVersion {
            fail("Unsupported snapshot schema version.")
        } catch {
            fail("Could not compare the snapshots. Check the file format and capture order.")
        }
    }

    private static func signed(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private static func read(_ path: String) throws -> TelemetrySnapshot {
        let maximumBytes = 8 * 1_024 * 1_024
        let file = URL(fileURLWithPath: path)
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadUnknown)
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let version = try decoder.decode(SchemaVersion.self, from: data)
        guard version.schemaVersion == TelemetrySnapshot.currentVersion else {
            throw SnapshotComparison.Error.unsupportedVersion
        }
        return try decoder.decode(TelemetrySnapshot.self, from: data)
    }

    private struct SchemaVersion: Decodable {
        let schemaVersion: Int
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(EXIT_FAILURE)
    }
}
