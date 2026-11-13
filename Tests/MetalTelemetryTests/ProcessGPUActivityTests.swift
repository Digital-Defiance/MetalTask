import Foundation
import Testing
@testable import MetalTelemetry

private let first = ProcessGPUActivity.Identity(pid: 42, startedSeconds: 100, startedMicroseconds: 1)
private let second = ProcessGPUActivity.Identity(pid: 43, startedSeconds: 100, startedMicroseconds: 2)

private func client(_ process: ProcessGPUActivity.Identity, _ counters: [UInt64]?)
    -> ProcessGPUActivitySampler.Client {
    .init(process: process, name: "Workload", counters: counters)
}

@Test func processGPUKeepsSurvivingClientDeltasWhenOtherClientsExit() throws {
    var sampler = ProcessGPUActivitySampler()
    let now = ContinuousClock.now
    let warmup = sampler.update(clients: [
        10: client(first, [800_000_000]),
        11: client(first, [50_000_000]),
        20: client(second, [100_000_000]),
    ], at: now)
    #expect(warmup.allSatisfy { $0.gpuMillisecondsPerSecond == nil })

    let running = sampler.update(clients: [
        10: client(first, [1_200_000_000]),
        11: client(first, [150_000_000]),
        20: client(second, [400_000_000]),
    ], at: now + .seconds(1))
    #expect(running.first { $0.process == first }?.gpuMillisecondsPerSecond == 500)
    #expect(running.first { $0.process == second }?.gpuMillisecondsPerSecond == 300)

    let afterExit = sampler.update(clients: [
        11: client(first, [350_000_000]),
    ], at: now + .seconds(2))
    let survivor = try #require(afterExit.first)
    #expect(afterExit.count == 1)
    #expect(survivor.process == first)
    #expect(survivor.gpuMillisecondsPerSecond == 200)
    #expect(survivor.partial)
}

@Test func processGPURejectsResetsNewClientsAndReusedPIDsButKeepsObservedZero() {
    var sampler = ProcessGPUActivitySampler()
    let now = ContinuousClock.now
    let reused = ProcessGPUActivity.Identity(pid: first.pid, startedSeconds: 101, startedMicroseconds: 1)
    _ = sampler.update(clients: [
        10: client(first, [100]),
        20: client(second, [100]),
        21: client(second, [200, 100]),
    ], at: now)
    let rows = sampler.update(clients: [
        10: client(reused, [200]),
        20: client(second, [100]),
        21: client(second, [300, 1]),
        22: client(second, [400]),
    ], at: now + .seconds(1))
    #expect(rows.first { $0.process == reused }?.gpuMillisecondsPerSecond == nil)
    #expect(rows.first { $0.process == second }?.gpuMillisecondsPerSecond == 0)
    #expect(rows.first { $0.process == second }?.partial == true)
}

@Test func processGPURejectsLongGapsAndMissingUsage() {
    var sampler = ProcessGPUActivitySampler()
    let now = ContinuousClock.now
    _ = sampler.update(clients: [10: client(first, [100])], at: now)
    let afterGap = sampler.update(clients: [10: client(first, [200])], at: now + .seconds(6))
    #expect(afterGap.first?.gpuMillisecondsPerSecond == nil)
    let missing = sampler.update(clients: [10: client(first, nil)], at: now + .seconds(7))
    #expect(missing.first?.gpuMillisecondsPerSecond == nil)
}

@Test func processGPUParsesCreatorAndStrictUnsignedCounters() {
    #expect(ProcessGPUActivitySampler.creatorPID("pid 42, Workload") == 42)
    #expect(ProcessGPUActivitySampler.creatorPID("pid 0, Workload") == nil)
    #expect(ProcessGPUActivitySampler.creatorPID("owner 42") == nil)
    #expect(ProcessGPUActivitySampler.decodeCounters([
        ["accumulatedGPUTime": NSNumber(value: UInt64.max)], ["accumulatedGPUTime": 0],
    ]) == [UInt64.max, 0])
    for value: Any in [true, -1, "5", 0.5, NSNull()] {
        #expect(ProcessGPUActivitySampler.decodeCounters([["accumulatedGPUTime": value]]) == nil)
    }
}
