import Foundation
import Network
import Testing
@testable import ModelInspection

@Test func decodesLoadedModelsWithOptionalMetadata() throws {
    let data = Data("""
        {"models":[{"name":"example:latest","digest":"abc","details":{"quantization_level":"Q4_K_M"},
        "context_length":4096,"size":8000000000,"size_vram":0},{"model":"older-model"}]}
        """.utf8)
    let models = try OllamaClient.decode(data)
    #expect(models == [
        OllamaModel(name: "example:latest", digest: "abc", quantization: "Q4_K_M",
                    contextLength: 4096, sizeBytes: 8_000_000_000, gpuSizeBytes: 0),
        OllamaModel(name: "older-model", digest: nil, quantization: nil,
                    contextLength: nil, sizeBytes: nil, gpuSizeBytes: nil),
    ])
    #expect(try OllamaClient.decode(Data(#"{"models":[]}"#.utf8)).isEmpty)
}

@Test(arguments: ["{}", #"{"models":[{}]}"#, #"{"models":[{"name":"model","size_vram":-1}]}"#])
func rejectsUnsupportedResponses(_ body: String) {
    #expect(throws: OllamaClient.Failure.invalidResponse) {
        try OllamaClient.decode(Data(body.utf8))
    }
}

@Test func fetchesFromLocalServer() async throws {
    let models = try await withServer(reply: response(body: #"{"models":[{"name":"local-test"}]}"#)) {
        try await OllamaClient(port: $0, timeout: 2).loadedModels()
    }
    #expect(models.map(\.name) == ["local-test"])
}

@Test func readsLlamaPropertiesThroughTheSharedLoopbackTransport() async throws {
    let properties = try await withServer(
        reply: response(body: #"{"total_slots":4}"#), expectedRequest: "GET /props HTTP/1.1"
    ) { port in
        try await LlamaServerClient(port: port).properties()
    }
    #expect(properties.totalSlots == 4)
}

@Test func rejectsRedirectAndOversizedResponse() async throws {
    try await withServer(reply: "HTTP/1.1 302 Found\r\nLocation: /another\r\nContent-Length: 0\r\n\r\n") { port -> Void in
        await #expect(throws: OllamaClient.Failure.redirect) {
            try await OllamaClient(port: port, timeout: 2).loadedModels()
        }
    }
    let body = String(repeating: "x", count: OllamaClient.responseLimit + 1)
    let chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        + String(body.utf8.count, radix: 16) + "\r\n" + body + "\r\n0\r\n\r\n"
    try await withServer(reply: chunked) { port -> Void in
        await #expect(throws: OllamaClient.Failure.responseTooLarge) {
            try await OllamaClient(port: port, timeout: 5).loadedModels()
        }
    }
}

@Test func timesOutWhenLocalServiceDoesNotRespond() async throws {
    try await withServer(reply: nil) { port -> Void in
        await #expect(throws: OllamaClient.Failure.timedOut) {
            try await OllamaClient(port: port, timeout: 0.3).loadedModels()
        }
    }
}

@Test func reportsConnectionFailureWhenServiceIsStopped() async throws {
    let listener = try makeListener()
    listener.newConnectionHandler = { $0.cancel() }
    let (states, continuation) = listenerStates(listener)
    defer { continuation.finish(); listener.cancel() }
    var iterator = states.makeAsyncIterator()
    let port = try await readyPort(listener, states: &iterator)
    listener.cancel()
    while let state = await iterator.next() {
        if case .cancelled = state { break }
    }
    await #expect(throws: OllamaClient.Failure.serviceUnavailable) {
        try await OllamaClient(port: port, timeout: 2).loadedModels()
    }
}

private func response(body: String) -> String {
    "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
}

private func makeListener() throws -> NWListener {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    return try NWListener(using: parameters)
}

private func listenerStates(_ listener: NWListener) -> (
    AsyncStream<NWListener.State>, AsyncStream<NWListener.State>.Continuation
) {
    let (states, continuation) = AsyncStream<NWListener.State>.makeStream()
    listener.stateUpdateHandler = { continuation.yield($0) }
    listener.start(queue: .global())
    return (states, continuation)
}

private func readyPort(
    _ listener: NWListener, states: inout AsyncStream<NWListener.State>.Iterator
) async throws -> UInt16 {
    while let state = await states.next() {
        switch state {
        case .ready: return try #require(listener.port?.rawValue)
        case .failed(let error): throw error
        default: continue
        }
    }
    throw CancellationError()
}

private func withServer<T>(
    reply: String?, expectedRequest: String? = nil, request: (UInt16) async throws -> T
) async throws -> T {
    let listener = try makeListener()
    let (connections, continuation) = AsyncStream<NWConnection>.makeStream()
    defer {
        continuation.finish()
        listener.cancel()
    }
    listener.newConnectionHandler = { continuation.yield($0) }
    let (states, stateContinuation) = listenerStates(listener)
    defer { stateContinuation.finish() }
    var iterator = states.makeAsyncIterator()
    let port = try await readyPort(listener, states: &iterator)
    async let serve: Void = {
        for await connection in connections {
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: expectedRequest?.utf8.count ?? 1, maximumLength: 4096) {
                data, _, complete, error in
                if complete || error != nil {
                    connection.cancel()
                    return
                }
                if let expectedRequest {
                    let requestLine = String(decoding: data ?? Data(), as: UTF8.self)
                    #expect(requestLine.hasPrefix(expectedRequest))
                }
                if let reply {
                    connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }
    }()
    do {
        let result = try await request(port)
        continuation.finish()
        await serve
        return result
    } catch {
        continuation.finish()
        await serve
        throw error
    }
}
