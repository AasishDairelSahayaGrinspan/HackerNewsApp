import Foundation
import os

protocol APIClientProtocol: Sendable {
    func fetch<T: Decodable & Sendable>(_ type: T.Type, endpoint: Endpoint) async throws -> T
    func fetchData(endpoint: Endpoint) async throws -> Data
}

// MARK: - APIClient

final class APIClient: APIClientProtocol, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.hacknews.app", category: "networking")

    init(baseURL: URL = URL(string: "https://hacker-news.firebaseio.com/v0/")!,
         session: URLSession? = nil,
         decoder: JSONDecoder = JSONDecoder()) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = true
            config.httpMaximumConnectionsPerHost = 12
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
        self.decoder = decoder
    }

    func fetch<T: Decodable & Sendable>(_ type: T.Type, endpoint: Endpoint) async throws -> T {
        let data = try await fetchData(endpoint: endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Decoding failed for \(endpoint.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }

    func fetchData(endpoint: Endpoint) async throws -> Data {
        guard let url = endpoint.url(baseURL: baseURL) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        #if DEBUG
        logger.debug("→ GET \(url.absoluteString, privacy: .public)")
        #endif

        // Retry once on transient failures for high-volume loads
        var lastError: Error?
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    // Retry on 5xx
                    if (500..<600).contains(http.statusCode), attempt == 0 {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        continue
                    }
                    logger.error("Server error \(http.statusCode) for \(url.absoluteString, privacy: .public)")
                    throw APIError.serverError(statusCode: http.statusCode)
                }
                #if DEBUG
                logger.debug("← \(http.statusCode) \(endpoint.path, privacy: .public) (\(data.count) bytes)")
                #endif
                return data
            } catch let err as APIError {
                throw err
            } catch let urlErr as URLError where urlErr.code == .timedOut {
                lastError = APIError.requestTimeout
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                throw APIError.requestTimeout
            } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet || urlErr.code == .networkConnectionLost {
                throw APIError.networkUnavailable
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw APIError.cancelled
            } catch {
                if Task.isCancelled { throw APIError.cancelled }
                lastError = error
                if attempt == 0, !(error is DecodingError) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }
                throw APIError.map(error)
            }
        }
        throw APIError.map(lastError ?? URLError(.unknown))
    }
}

// MARK: - Mock for Testing

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var stubbedResponses: [String: Data] = [:]
    var stubbedError: APIError?
    var requestCount: [String: Int] = [:]

    func stub<T: Encodable>(_ value: T, for path: String) throws {
        let data = try JSONEncoder().encode(value)
        stubbedResponses[path] = data
    }

    func fetch<T: Decodable & Sendable>(_ type: T.Type, endpoint: Endpoint) async throws -> T {
        if let err = stubbedError { throw err }
        requestCount[endpoint.path, default: 0] += 1
        guard let data = stubbedResponses[endpoint.path] else {
            throw APIError.itemNotFound(-1)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchData(endpoint: Endpoint) async throws -> Data {
        if let err = stubbedError { throw err }
        requestCount[endpoint.path, default: 0] += 1
        guard let data = stubbedResponses[endpoint.path] else {
            throw APIError.itemNotFound(-1)
        }
        return data
    }
}
