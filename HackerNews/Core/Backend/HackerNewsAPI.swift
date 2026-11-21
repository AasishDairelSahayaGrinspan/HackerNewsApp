import Foundation
import os

protocol HackerNewsAPIProtocol: Sendable {
    func fetchStoryIDs(for feed: FeedType) async throws -> [Int]
    func fetchItem(id: Int) async throws -> HNItemDTO
    func fetchItems(ids: [Int], maxConcurrency: Int) async throws -> [HNItemDTO]
    func fetchMaxItemID() async throws -> Int
    func metrics() async -> APIMetrics
}

actor HackerNewsAPI: HackerNewsAPIProtocol {
    private let client: any APIClientProtocol
    private let logger = Logger(subsystem: "com.hacknews.app", category: "networking")
    private var inFlight: [Int: Task<HNItemDTO, Error>] = [:]
    private var itemsParsed: UInt64 = 0

    init(client: any APIClientProtocol = APIClient()) {
        self.client = client
    }

    func fetchStoryIDs(for feed: FeedType) async throws -> [Int] {
        try await client.fetch([Int].self, endpoint: Endpoint(path: feed.endpointPath))
    }

    func fetchItem(id: Int) async throws -> HNItemDTO {
        if let existing = inFlight[id] {
            return try await existing.value
        }

        let task = Task<HNItemDTO, Error> { [client] in
            let data = try await client.fetchData(endpoint: Endpoint(path: "item/\(id).json"))
            if let text = String(data: data, encoding: .utf8),
               text.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                throw APIError.itemNotFound(id)
            }
            do {
                return try JSONDecoder().decode(HNItemDTO.self, from: data)
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }
        }
        inFlight[id] = task

        do {
            let item = try await task.value
            inFlight[id] = nil
            itemsParsed += 1
            return item
        } catch {
            inFlight[id] = nil
            throw error
        }
    }

    /// Controlled concurrency with chunked batching. IDs are deduplicated and
    /// the original order is preserved.
    func fetchItems(ids: [Int], maxConcurrency: Int = 12) async throws -> [HNItemDTO] {
        guard !ids.isEmpty else { return [] }
        let unique = ids.uniqued()
        var results: [Int: HNItemDTO] = [:]

        let chunks = unique.chunked(into: 30)
        for (index, chunk) in chunks.enumerated() {
            try await withThrowingTaskGroup(of: (Int, HNItemDTO?).self) { group in
                let semaphore = AsyncSemaphore(value: maxConcurrency)
                for id in chunk {
                    group.addTask {
                        await semaphore.wait()
                        let result: (Int, HNItemDTO?)
                        do {
                            result = (id, try await self.fetchItem(id: id))
                        } catch let api as APIError {
                            if case .itemNotFound = api {
                                result = (id, nil)
                            } else {
                                self.logger.warning("Item \(id) failed: \(api.localizedDescription, privacy: .public)")
                                result = (id, nil)
                            }
                        } catch {
                            self.logger.warning("Item \(id) failed: \(error.localizedDescription, privacy: .public)")
                            result = (id, nil)
                        }
                        await semaphore.signal()
                        return result
                    }
                }

                for try await (id, item) in group {
                    if let item { results[id] = item }
                }
            }

            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        return unique.compactMap { results[$0] }
    }

    func fetchMaxItemID() async throws -> Int {
        try await client.fetch(Int.self, endpoint: Endpoint(path: "maxitem.json"))
    }

    func metrics() async -> APIMetrics {
        var metrics = client.metricsSnapshot()
        metrics.itemsParsed = itemsParsed
        return metrics
    }
}

// MARK: - Async semaphore

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(1, value)
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }
}

// MARK: - Helpers

extension Array where Element == Int {
    func uniqued() -> [Int] {
        var seen = Set<Int>()
        return filter { seen.insert($0).inserted }
    }

    func chunked(into size: Int) -> [[Int]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Mock

final class MockHackerNewsAPI: HackerNewsAPIProtocol, @unchecked Sendable {
    var storyIDs: [FeedType: [Int]] = [:]
    var items: [Int: HNItemDTO] = [:]
    var shouldFail = false
    var errorToThrow: APIError = .networkUnavailable
    private var metricsValue = APIMetrics()

    func fetchStoryIDs(for feed: FeedType) async throws -> [Int] {
        if shouldFail { throw errorToThrow }
        return storyIDs[feed] ?? []
    }

    func fetchItem(id: Int) async throws -> HNItemDTO {
        if shouldFail { throw errorToThrow }
        guard let item = items[id] else { throw APIError.itemNotFound(id) }
        metricsValue.itemsParsed += 1
        return item
    }

    func fetchItems(ids: [Int], maxConcurrency: Int = 8) async throws -> [HNItemDTO] {
        if shouldFail { throw errorToThrow }
        return ids.compactMap { items[$0] }
    }

    func fetchMaxItemID() async throws -> Int {
        if shouldFail { throw errorToThrow }
        return items.keys.max() ?? 0
    }

    func metrics() async -> APIMetrics { metricsValue }
}
