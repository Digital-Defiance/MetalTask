import Darwin
import Foundation

public enum GraphicsFootprint: Codable, Equatable, Sendable {
    case bytes(UInt64)
    case noGraphicsCategory
    case permissionDenied
    case processChanged
    case timedOut
    case unsupported
    case failed

    public var byteCount: UInt64? {
        if case let .bytes(value) = self { return value }
        return nil
    }
}

/// Serializes footprint probes across window lifetimes.
public actor GraphicsFootprintReader {
    private static let outputLimit = 2 * 1_024 * 1_024
    private var busy = false

    public init() {}

    public func capture(pid: Int32) async -> GraphicsFootprint? {
        guard pid > 0 else { return .processChanged }
        guard let identity = ProcessGPUActivitySampler.processInfo(pid: pid)?.0 else {
            if kill(pid, 0) == 0 { return .failed }
            return errno == EPERM ? .permissionDenied : .processChanged
        }
        return await capture(for: identity)
    }

    public func capture(for identity: ProcessGPUActivity.Identity) async -> GraphicsFootprint? {
        guard !busy, !Task.isCancelled else { return nil }
        busy = true
        defer { busy = false }
        guard ProcessGPUActivitySampler.processInfo(pid: identity.pid)?.0 == identity else {
            return .processChanged
        }
        do {
            let result = try await Self.run(pid: identity.pid)
            guard ProcessGPUActivitySampler.processInfo(pid: identity.pid)?.0 == identity else {
                return .processChanged
            }
            return result
        } catch is CancellationError {
            return nil
        } catch {
            return .failed
        }
    }

    private static func run(pid: Int32) async throws -> GraphicsFootprint {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("MetalTask-\(UUID())")
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: directory) }
        let json = directory.appendingPathComponent("footprint.json")
        let errors = directory.appendingPathComponent("stderr")
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
        command.arguments = ["--format", "bytes", "--pid", String(pid), "--json", json.path]
        command.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        command.standardInput = FileHandle.nullDevice
        command.standardOutput = FileHandle.nullDevice
        guard manager.createFile(atPath: errors.path, contents: nil) else { return .failed }
        let stderr = try FileHandle(forWritingTo: errors)
        defer { try? stderr.close() }
        command.standardError = stderr
        switch try await runHelper(command, watching: [json, errors]) {
        case .timedOut: return .timedOut
        case .outputLimit: return .failed
        case .exited(0): return decode(try readBounded(json), pid: pid)
        case .exited:
            let message = String(decoding: (try? readBounded(errors)) ?? Data(), as: UTF8.self)
            if message.contains("Unable to analyze process with pid \(pid) (try as root?)")
                || message.localizedCaseInsensitiveContains("permission denied") {
                return .permissionDenied
            }
            return .failed
        }
    }

    enum HelperResult: Equatable {
        case exited(Int32)
        case timedOut
        case outputLimit
    }

    static func runHelper(
        _ command: Process, watching files: [URL] = [], timeout: Duration = .seconds(3),
        onStart: (Int32) -> Void = { _ in }
    ) async throws -> HelperResult {
        try Task.checkCancellation()
        try command.run()
        defer {
            if command.isRunning { kill(command.processIdentifier, SIGKILL) }
            command.waitUntilExit()
        }
        onStart(command.processIdentifier)
        let deadline = ContinuousClock.now + timeout
        while command.isRunning {
            if ContinuousClock.now >= deadline { return .timedOut }
            if files.contains(where: exceedsLimit) { return .outputLimit }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        if files.contains(where: exceedsLimit) { return .outputLimit }
        return .exited(command.terminationStatus)
    }

    private static func exceedsLimit(_ file: URL) -> Bool {
        ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > outputLimit
    }

    private static func readBounded(_ file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: outputLimit + 1) ?? Data()
        guard data.count <= outputLimit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    static func decode(_ data: Data, pid: Int32) -> GraphicsFootprint {
        guard let report = (try? JSONDecoder().decode(Report.self, from: data)),
              report.unit == "byte", report.bytesPerUnit == 1,
              report.errors.isEmpty, report.warnings.isEmpty,
              report.processes.count == 1, let process = report.processes.first,
              process.pid == pid, !process.categories.isEmpty else { return .unsupported }
        let graphics = process.categories.filter { $0.key.hasSuffix(" (graphics)") }
        guard !graphics.isEmpty else { return .noGraphicsCategory }
        var total: UInt64 = 0
        for category in graphics.values {
            let (sum, overflow) = total.addingReportingOverflow(category.dirty)
            guard !overflow else { return .unsupported }
            total = sum
        }
        return .bytes(total)
    }

    private struct Report: Decodable {
        let unit: String
        let bytesPerUnit: Int
        let errors: [String]
        let warnings: [String]
        let processes: [Target]

        enum CodingKeys: String, CodingKey {
            case unit, errors, warnings, processes
            case bytesPerUnit = "bytes per unit"
        }
    }

    private struct Target: Decodable {
        let pid: Int32
        let categories: [String: Category]
    }

    private struct Category: Decodable {
        let dirty: UInt64
    }
}
