import Foundation

public struct OllamaModel: Equatable, Sendable {
    public let name: String
    public let digest: String?
    public let quantization: String?
    public let contextLength: UInt64?
    public let sizeBytes: UInt64?
    public let gpuSizeBytes: UInt64?
}

public struct OllamaClient: Sendable {
    public typealias Failure = LocalModelRequestFailure
    static let responseLimit = LocalModelRequest.responseLimit
    private let port: UInt16
    private let timeout: TimeInterval

    public init() {
        self.init(port: 11_434, timeout: 3)
    }

    // Keep the destination local even when using a test server on a different port.
    init(port: UInt16, timeout: TimeInterval) {
        self.port = port
        self.timeout = timeout
    }

    public func loadedModels() async throws -> [OllamaModel] {
        try Self.decode(await LocalModelRequest.get(port: port, path: "/api/ps", timeout: timeout))
    }

    static func decode(_ data: Data) throws -> [OllamaModel] {
        guard data.count <= responseLimit else { throw Failure.responseTooLarge }
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              payload.models.count <= 256 else { throw Failure.invalidResponse }
        return try payload.models.map { entry in
            guard let name = [entry.name, entry.model].compactMap({ $0 }).first(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }), name.utf8.count <= 512 else { throw Failure.invalidResponse }
            return OllamaModel(name: name, digest: entry.digest, quantization: entry.details?.quantization,
                               contextLength: entry.contextLength, sizeBytes: entry.size,
                               gpuSizeBytes: entry.gpuSize)
        }
    }

    private struct Response: Decodable {
        let models: [Entry]
    }

    private struct Entry: Decodable {
        let name: String?
        let model: String?
        let digest: String?
        let details: Details?
        let contextLength: UInt64?
        let size: UInt64?
        let gpuSize: UInt64?

        enum CodingKeys: String, CodingKey {
            case name, model, digest, details, size
            case contextLength = "context_length"
            case gpuSize = "size_vram"
        }
    }

    private struct Details: Decodable {
        let quantization: String?

        enum CodingKeys: String, CodingKey {
            case quantization = "quantization_level"
        }
    }
}
