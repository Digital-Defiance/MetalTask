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
    public enum Failure: Error, Equatable, Sendable {
        case serviceUnavailable
        case timedOut
        case redirect
        case httpStatus(Int)
        case responseTooLarge
        case invalidResponse
    }

    static let responseLimit = 256 * 1_024
    private let endpoint: URL
    private let timeout: TimeInterval

    public init() {
        self.init(port: 11_434, timeout: 3)
    }

    // Keep the destination local even when using a test server on a different port.
    init(port: UInt16, timeout: TimeInterval) {
        endpoint = URL(string: "http://127.0.0.1:\(port)/api/ps")!
        self.timeout = timeout
    }

    public func loadedModels() async throws -> [OllamaModel] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0,
        ]
        let session = URLSession(configuration: configuration, delegate: LocalRequestDelegate(),
                                 delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            if (300..<400).contains(http.statusCode) { throw Failure.redirect }
            guard http.statusCode == 200 else { throw Failure.httpStatus(http.statusCode) }
            guard http.expectedContentLength <= Self.responseLimit else { throw Failure.responseTooLarge }

            var body = Data()
            for try await byte in bytes {
                guard body.count < Self.responseLimit else { throw Failure.responseTooLarge }
                body.append(byte)
            }
            try Task.checkCancellation()
            return try Self.decode(body)
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? Failure.timedOut : Failure.serviceUnavailable
        }
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

private final class LocalRequestDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
