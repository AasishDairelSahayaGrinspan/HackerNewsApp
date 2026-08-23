import Foundation
import os

protocol HackerNewsAPIProtocol {
    func fetchStoryIDs(for feed: FeedType) async throws -> [Int]
    func fetchItem(id: Int) async throws -> HNItemDTO
    func fetchItems(ids: [Int], maxConcurrency: Int) async throws -> [HNItemDTO]
    func fetchMaxItemID() async throws -> Int
}

// MARK: - Implementation

actor HackerNewsAPI: HackerNewsAPIProtocol {
    private let client: any APIClientProtocol
    private let logger = Logger(subsystem: "com.hacknews.app", category: "networking")

    // Deduplication cache for in-flight requests
    private var inFlight: [Int: Task<HNItemDTO, Error>] = [:]

    init(client: any APIClientProtocol = APIClient()) {
        self.client = client
    }

    func fetchStoryIDs(for feed: FeedType) async throws -> [Int] {
        let endpoint = Endpoint(path: feed.endpointPath)
        return try await client.fetch([Int].self, endpoint: endpoint)
    }

    func fetchItem(id: Int) async throws -> HNItemDTO {
        if let existing = inFlight[id] {
            return try await existing.value
        }
        let task = Task<HNItemDTO, Error> {
            let endpoint = Endpoint(path: "item/\(id).json")
            let data = try await client.fetchData(endpoint: endpoint)
            if data.count <= 4, let str = String(data: data, encoding: .utf8), str.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                throw APIError.itemNotFound(id)
            }
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(HNItemDTO.self, from: data)
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }
        }
        inFlight[id] = task
        defer { inFlight.removeValue(forKey: id) }
        return try await task.value
    }

    /// Controlled concurrency fetch with chunked batching (C++ core)
    func fetchItems(ids: [Int], maxConcurrency: Int = 12) async throws -> [HNItemDTO] {
        guard !ids.isEmpty else { return [] }
        // C++ deduplication (HNCppEngine::deduplicateIDs) - single source of truth
        let unique = CppEngine.deduplicate(ids)
        // C++ chunking (HNCppEngine::chunkIDs) for high-volume 100+ comments
        let chunks = CppEngine.chunk(unique, size: 30)
        var results: [Int: HNItemDTO] = [:]

        for chunk in chunks {
            // Each chunk runs with bounded concurrency
            try await withThrowingTaskGroup(of: (Int, HNItemDTO?).self) { group in
                let semaphore = AsyncSemaphore(value: maxConcurrency)
                for id in chunk {
                    group.addTask {
                        await semaphore.wait()
                        var result: (Int, HNItemDTO?)
                        do {
                            let item = try await self.fetchItem(id: id)
                            result = (id, item)
                        } catch {
                            // Deleted/dead items return nil but don't fail whole batch
                            if let apiErr = error as? APIError, case .itemNotFound = apiErr {
                                // ok
                            } else {
                                self.logger.warning("Failed to fetch item \(id): \(error.localizedDescription, privacy: .public)")
                            }
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
            // Tiny breather to avoid hammering Firebase on huge stories
            if chunks.count > 1 {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        return ids.compactMap { results[$0] }.uniquedByID()
    }

    func fetchMaxItemID() async throws -> Int {
        let endpoint = Endpoint(path: "maxitem.json")
        return try await client.fetch(Int.self, endpoint: endpoint)
    }
}

// MARK: - AsyncSemaphore

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.value = value }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
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

private extension Array where Element == HNItemDTO {
    func uniquedByID() -> [HNItemDTO] {
        var seen = Set<Int>()
        return filter { seen.insert($0.id).inserted }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Mock API

final class MockHackerNewsAPI: HackerNewsAPIProtocol, @unchecked Sendable {
    var storyIDs: [FeedType: [Int]] = [:]
    var items: [Int: HNItemDTO] = [:]
    var shouldFail = false
    var errorToThrow: APIError = .networkUnavailable

    func fetchStoryIDs(for feed: FeedType) async throws -> [Int] {
        if shouldFail { throw errorToThrow }
        return storyIDs[feed] ?? []
    }

    func fetchItem(id: Int) async throws -> HNItemDTO {
        if shouldFail { throw errorToThrow }
        guard let item = items[id] else { throw APIError.itemNotFound(id) }
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
}
