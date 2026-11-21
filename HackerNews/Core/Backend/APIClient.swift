import Foundation
import os

protocol APIClientProtocol: Sendable {
    func fetch<T: Decodable & Sendable>(_ type: T.Type, endpoint: Endpoint) async throws -> T
    func fetchData(endpoint: Endpoint) async throws -> Data
    func metricsSnapshot() -> APIMetrics
}

final class APIClient: APIClientProtocol, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.hacknews.app", category: "networking")

    private let metricsLock = NSLock()
    private var _metrics = APIMetrics()

    init(baseURL: URL = URL(string: "https://hacker-news.firebaseio.com/v0/")!,
         session: URLSession? = nil,
         decoder: JSONDecoder = JSONDecoder()) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = true
            configuration.httpMaximumConnectionsPerHost = 12
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = decoder
    }

    func metricsSnapshot() -> APIMetrics {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return _metrics
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

        mutateMetrics {
            $0.requests += 1
            $0.inFlight += 1
        }
        let started = Date()
        defer {
            let elapsed = Date().timeIntervalSince(started) * 1000
            mutateMetrics {
                $0.inFlight = max(0, $0.inFlight - 1)
                $0.lastLatencyMs = elapsed
                $0.totalLatencyMs += elapsed
                $0.latencySamples += 1
            }
        }

        #if DEBUG
        logger.debug("GET \(url.absoluteString, privacy: .public)")
        #endif

        var lastError: APIError = .unknown("Request failed")

        for attempt in 0...2 {
            if Task.isCancelled {
                lastError = .cancelled
                break
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw APIError.serverError(statusCode: http.statusCode)
                }
                mutateMetrics { $0.bytesReceived += UInt64(data.count) }
                #if DEBUG
                logger.debug("\(http.statusCode, privacy: .public) \(endpoint.path, privacy: .public) (\(data.count) bytes)")
                #endif
                return data
            } catch let api as APIError {
                lastError = api
            } catch let urlError as URLError {
                lastError = APIError.map(urlError)
            } catch {
                lastError = APIError.map(error)
            }

            guard lastError.isRetryable, attempt < 2, !Task.isCancelled else {
                break
            }

            mutateMetrics { $0.retries += 1 }
            let backoff: UInt64 = attempt == 0 ? 400_000_000 : 800_000_000
            try? await Task.sleep(nanoseconds: backoff)
        }

        mutateMetrics { $0.failures += 1 }
        #if DEBUG
        logger.error("Request failed \(endpoint.path, privacy: .public): \(lastError.localizedDescription, privacy: .public)")
        #endif
        throw lastError
    }

    private func mutateMetrics(_ body: (inout APIMetrics) -> Void) {
        metricsLock.lock()
        body(&_metrics)
        metricsLock.unlock()
    }
}

// MARK: - Mock

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var stubbedResponses: [String: Data] = [:]
    var stubbedError: APIError?
    var requestCount: [String: Int] = [:]
    private var _metrics = APIMetrics()

    func stub<T: Encodable>(_ value: T, for path: String) throws {
        stubbedResponses[path] = try JSONEncoder().encode(value)
    }

    func fetch<T: Decodable & Sendable>(_ type: T.Type, endpoint: Endpoint) async throws -> T {
        if let error = stubbedError { throw error }
        requestCount[endpoint.path, default: 0] += 1
        guard let data = stubbedResponses[endpoint.path] else {
            throw APIError.itemNotFound(-1)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchData(endpoint: Endpoint) async throws -> Data {
        if let error = stubbedError { throw error }
        requestCount[endpoint.path, default: 0] += 1
        guard let data = stubbedResponses[endpoint.path] else {
            throw APIError.itemNotFound(-1)
        }
        return data
    }

    func metricsSnapshot() -> APIMetrics { _metrics }
}
