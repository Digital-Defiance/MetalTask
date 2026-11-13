import Darwin
import Foundation
import IOKit
import Metal

public struct ProcessGPUActivity: Codable, Identifiable, Sendable {
    public struct Identity: Codable, Hashable, Sendable {
        public let pid: Int32
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
    }

    public let process: Identity
    public let name: String
    /// GPU time per elapsed second for comparable, observable clients.
    public let gpuMillisecondsPerSecond: Double?
    public let partial: Bool
    public var id: Identity { process }
}

public struct ProcessGPUActivitySampler: Sendable {
    public struct Sample: Codable, Sendable {
        public let processes: [ProcessGPUActivity]
        public let partial: Bool
    }

    struct Client: Sendable {
        let process: ProcessGPUActivity.Identity
        let name: String
        let counters: [UInt64]?
    }

    private var previous: [UInt64: Client] = [:]
    private var previousTime: ContinuousClock.Instant?

    public init() {}

    /// Reads the default accelerator synchronously. Sample off the main actor.
    /// A nil sample means the accelerator or its client enumeration is unavailable.
    public mutating func capture() -> Sample? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let accelerator = copyAccelerator(registryID: device.registryID) else {
            reset()
            return nil
        }
        defer { IOObjectRelease(accelerator) }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            reset()
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var identities: [Int32: (ProcessGPUActivity.Identity, String)] = [:]
        var inaccessiblePIDs: Set<Int32> = []
        var clients: [UInt64: Client] = [:]
        var partial = false
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard IOObjectConformsTo(service, "AGXDeviceUserClient") != 0 else { continue }
            var clientID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &clientID) == KERN_SUCCESS,
                  let pid = Self.creatorPID(Self.property("IOUserClientCreator", of: service)) else {
                partial = true
                continue
            }
            if identities[pid] == nil, !inaccessiblePIDs.contains(pid) {
                if let process = Self.processInfo(pid: pid) {
                    identities[pid] = process
                } else {
                    inaccessiblePIDs.insert(pid)
                }
            }
            guard let (process, name) = identities[pid] else {
                partial = true
                continue
            }
            clients[clientID] = Client(
                process: process, name: name,
                counters: Self.decodeCounters(Self.property("AppUsage", of: service))
            )
        }
        guard IOIteratorIsValid(iterator) != 0 else {
            reset()
            return nil
        }
        // Recheck identities after collection so a process that exited or was
        // replaced during the scan cannot receive that scan's client counters.
        let changed = Set(identities.compactMap { pid, info in
            Self.processInfo(pid: pid)?.0 == info.0 ? nil : pid
        })
        if !changed.isEmpty {
            clients = clients.filter { !changed.contains($0.value.process.pid) }
            partial = true
        }
        return Sample(processes: update(clients: clients, at: .now), partial: partial)
    }

    mutating func update(clients: [UInt64: Client], at time: ContinuousClock.Instant) -> [ProcessGPUActivity] {
        let elapsed = previousTime.map { $0.duration(to: time) }
        defer {
            previous = clients
            previousTime = time
        }
        let comparable = elapsed.map { $0 > .zero && $0 <= .seconds(5) } ?? false
        let elapsedSeconds = elapsed.map {
            Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18
        } ?? 0
        let grouped = Dictionary(grouping: clients, by: { $0.value.process })
        let disappeared = Set(previous.compactMap { id, client in
            clients[id]?.process == client.process ? nil : client.process
        })
        return grouped.map { process, entries in
            var deltas: [UInt64] = []
            if comparable {
                deltas = entries.compactMap { id, client in
                    guard let old = previous[id], old.process == process else { return nil }
                    return Self.delta(from: old.counters, to: client.counters)
                }
            }
            let gpuMilliseconds = deltas.reduce(0.0) { $0 + Double($1) / 1_000_000 }
            return ProcessGPUActivity(
                process: process,
                name: entries[0].value.name,
                gpuMillisecondsPerSecond: deltas.isEmpty ? nil : gpuMilliseconds / elapsedSeconds,
                partial: deltas.count < entries.count || disappeared.contains(process)
            )
        }
    }

    private mutating func reset() {
        previous = [:]
        previousTime = nil
    }

    private static func delta(from old: [UInt64]?, to current: [UInt64]?) -> UInt64? {
        guard let old, let current, old.count == current.count else { return nil }
        var total: UInt64 = 0
        for (before, after) in zip(old, current) {
            guard after >= before else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(after - before)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }

    static func decodeCounters(_ value: Any?) -> [UInt64]? {
        guard let records = value as? [[String: Any]], !records.isEmpty else { return nil }
        var counters: [UInt64] = []
        for record in records {
            guard let number = record["accumulatedGPUTime"] as? NSNumber,
                  CFGetTypeID(number) == CFNumberGetTypeID(),
                  let counter = UInt64(number.stringValue) else { return nil }
            counters.append(counter)
        }
        return counters
    }

    static func creatorPID(_ value: Any?) -> Int32? {
        guard let value = value as? String, value.hasPrefix("pid "),
              let token = value.dropFirst(4).split(separator: ",", omittingEmptySubsequences: false).first,
              let pid = Int32(token), pid > 0 else { return nil }
        return pid
    }

    private static func property(_ key: String, of service: io_registry_entry_t) -> CFTypeRef? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func processInfo(pid: Int32) -> (ProcessGPUActivity.Identity, String)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_start_tvsec > 0 else { return nil }
        let identity = ProcessGPUActivity.Identity(
            pid: pid, startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec
        )
        let name = withUnsafeBytes(of: info.pbi_name) {
            String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return (identity, name.isEmpty ? "PID \(pid)" : name)
    }
}
