import Foundation

public enum LocalModelRequestFailure: Error, Equatable, Sendable {
    case serviceUnavailable
    case timedOut
    case redirect
    case httpStatus(Int)
    case responseTooLarge
    case invalidResponse
}

enum LocalModelRequest {
    typealias Failure = LocalModelRequestFailure
    static let responseLimit = 256 * 1_024

    static func get(port: UInt16, path: String, timeout: TimeInterval, token: String? = nil) async throws -> Data {
        let endpoint = URL(string: "http://127.0.0.1:\(port)\(path)")!
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
            if let token, !token.isEmpty {
                guard token.utf8.count <= 4096, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
                    throw Failure.invalidResponse
                }
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
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
            return body
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? Failure.timedOut : Failure.serviceUnavailable
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
