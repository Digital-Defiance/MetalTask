import Foundation
import Darwin
import Testing
@testable import MetalTelemetry

private func report(
    _ categories: String, unit: String = "byte", pid: Int32 = 42, errors: String = "[]"
) -> Data {
    Data("""
    {"unit":"\(unit)","bytes per unit":1,"errors":\(errors),"warnings":[],
     "processes":[{"pid":\(pid),"categories":{\(categories)}}]}
    """.utf8)
}

@Test func footprintSumsOnlyDirtyGraphicsCategories() {
    let data = report("""
    "IOAccelerator (graphics)":{"dirty":475136,"wired":475136},
    "Owned physical footprint (unmapped) (graphics)":{"dirty":234881024},
    "GPU Carveout (reserved)":{"dirty":777}
    """)
    #expect(GraphicsFootprintReader.decode(data, pid: 42) == .bytes(235_356_160))
}

@Test func footprintDistinguishesMissingGraphicsFromObservedZero() {
    let absent = report(#""stack":{"dirty":16384}"#)
    let zero = report(#""IOAccelerator (graphics)":{"dirty":0}"#)
    #expect(GraphicsFootprintReader.decode(absent, pid: 42) == .noGraphicsCategory)
    #expect(GraphicsFootprintReader.decode(zero, pid: 42) == .bytes(0))
}

@Test func footprintRejectsPartialMismatchedAndOverflowingData() {
    let category = #""IOAccelerator (graphics)":{"dirty":1}"#
    let overflow = report("""
    "A (graphics)":{"dirty":18446744073709551615},"B (graphics)":{"dirty":1}
    """)
    for data in [report(category, unit: "page"), report(category, pid: 43),
                 report(category, errors: #"["incomplete"]"#), overflow,
                 report(#""IOAccelerator (graphics)":{"dirty":-1}"#), Data()] {
        #expect(GraphicsFootprintReader.decode(data, pid: 42) == .unsupported)
    }
}

@Test func footprintHelperIsReapedAfterCancellation() async throws {
    let (started, continuation) = AsyncStream<Int32>.makeStream()
    let task = Task {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/sleep")
        command.arguments = ["30"]
        defer { continuation.finish() }
        return try await GraphicsFootprintReader.runHelper(command) { continuation.yield($0) }
    }
    defer { task.cancel() }
    var iterator = started.makeAsyncIterator()
    let pid = try #require(await iterator.next())
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}

@Test func footprintHelperIsReapedAfterTimeout() async throws {
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/bin/sleep")
    command.arguments = ["30"]
    let result = try await GraphicsFootprintReader.runHelper(command, timeout: .milliseconds(100))
    #expect(result == .timedOut)
    #expect(kill(command.processIdentifier, 0) == -1)
    #expect(errno == ESRCH)
}
