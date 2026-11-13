import Foundation

public struct LlamaServerProperties: Equatable, Sendable {
    public let modelFilename: String?
    public let contextLength: UInt64?
    public let totalSlots: UInt64?
    public let isSleeping: Bool?
}

public struct LlamaServerClient: Sendable {
    private let port: UInt16

    public init(port: UInt16 = 8080) {
        self.port = port
    }

    public func properties() async throws -> LlamaServerProperties {
        // A model query can autoload a model on a router. Inspect only server-wide properties.
        try Self.decode(await LocalModelRequest.get(port: port, path: "/props", timeout: 3))
    }

    static func decode(_ data: Data) throws -> LlamaServerProperties {
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LocalModelRequestFailure.invalidResponse
        }
        let name = payload.modelPath?.split(separator: "/").last.map(String.init)
        let context = payload.generationSettings?.contextLength
        guard name != nil || context != nil || payload.totalSlots != nil || payload.isSleeping != nil else {
            throw LocalModelRequestFailure.invalidResponse
        }
        return LlamaServerProperties(
            modelFilename: name, contextLength: context, totalSlots: payload.totalSlots,
            isSleeping: payload.isSleeping
        )
    }

    private struct Response: Decodable {
        let modelPath: String?
        let totalSlots: UInt64?
        let isSleeping: Bool?
        let generationSettings: GenerationSettings?

        enum CodingKeys: String, CodingKey {
            case modelPath = "model_path"
            case totalSlots = "total_slots"
            case isSleeping = "is_sleeping"
            case generationSettings = "default_generation_settings"
        }
    }

    private struct GenerationSettings: Decodable {
        let contextLength: UInt64?

        enum CodingKeys: String, CodingKey {
            case contextLength = "n_ctx"
        }
    }
}
