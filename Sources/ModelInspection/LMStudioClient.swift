import Foundation

public struct LMStudioInstance: Equatable, Sendable {
    public let id: String
    public let modelName: String
    public let architecture: String?
    public let quantization: String?
    public let contextLength: UInt64?
    public let kvCacheOnGPU: Bool?
}

public struct LMStudioClient: Sendable {
    private let port: UInt16
    private let token: String?

    public init(port: UInt16 = 1234, token: String? = nil) {
        self.port = port
        self.token = token
    }

    public func loadedInstances() async throws -> [LMStudioInstance] {
        try Self.decode(await LocalModelRequest.get(port: port, path: "/api/v1/models", timeout: 3, token: token))
    }

    static func decode(_ data: Data) throws -> [LMStudioInstance] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LocalModelRequestFailure.invalidResponse
        }
        return response.models.flatMap { model in
            model.loadedInstances.map {
                LMStudioInstance(
                    id: $0.id, modelName: model.displayName ?? model.key ?? $0.id,
                    architecture: model.architecture, quantization: model.quantization?.name,
                    contextLength: $0.config?.contextLength, kvCacheOnGPU: $0.config?.offloadKvCacheToGpu
                )
            }
        }
    }

    private struct Response: Decodable {
        let models: [Model]
    }

    private struct Model: Decodable {
        let key: String?
        let displayName: String?
        let architecture: String?
        let quantization: Quantization?
        let loadedInstances: [Instance]

        enum CodingKeys: String, CodingKey {
            case key, architecture, quantization
            case displayName = "display_name"
            case loadedInstances = "loaded_instances"
        }
    }

    private struct Quantization: Decodable {
        let name: String?
    }

    private struct Instance: Decodable {
        let id: String
        let config: Configuration?
    }

    private struct Configuration: Decodable {
        let contextLength: UInt64?
        let offloadKvCacheToGpu: Bool?

        enum CodingKeys: String, CodingKey {
            case contextLength = "context_length"
            case offloadKvCacheToGpu = "offload_kv_cache_to_gpu"
        }
    }
}
