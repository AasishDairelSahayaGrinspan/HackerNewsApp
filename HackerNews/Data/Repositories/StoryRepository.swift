import Foundation
import SwiftData
import os

@MainActor
protocol StoryRepositoryProtocol {
    func stories(for feed: FeedType, page: Int, pageSize: Int) async -> LoadState<[CachedStory]>
    func refresh(feed: FeedType) async -> LoadState<[CachedStory]>
    func fetchStory(id: Int) async throws -> CachedStory
    func toggleSave(storyID: Int) -> Bool
    func isSaved(storyID: Int) -> Bool
    func search(query: String) -> [CachedStory]
}

@MainActor
final class StoryRepository: StoryRepositoryProtocol {
    private let api: any HackerNewsAPIProtocol
    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "com.hacknews.app", category: "cache")

    private var loadedIDs: [FeedType: [Int]] = [:]
    private let pageSizeDefault = 30

    init(api: any HackerNewsAPIProtocol = HackerNewsAPI(), persistence: PersistenceController) {
        self.api = api
        self.persistence = persistence
    }

    convenience init(api: any HackerNewsAPIProtocol = HackerNewsAPI()) {
        self.init(api: api, persistence: PersistenceController.shared)
    }

    func stories(for feed: FeedType, page: Int = 0, pageSize: Int = 30) async -> LoadState<[CachedStory]> {
        let cached = persistence.fetchStories(for: feed)
        if !cached.isEmpty && page == 0 {
            let lastFetched = persistence.lastFetched(for: feed)
            let freshness = CachePolicy.freshness(lastFetched: lastFetched)
            if freshness == .fresh {
                logger.info("Cache HIT fresh for \(feed.rawValue, privacy: .public)")
                return .loaded(cached)
            }
            if freshness == .stale || freshness == .expired {
                Task { _ = await self.refresh(feed: feed) }
                return .loaded(cached)
            }
        }
        if cached.isEmpty {
            return await refresh(feed: feed)
        }
        let start = page * pageSize
        guard start < cached.count else { return .loaded(cached) }
        let end = min(start + pageSize, cached.count)
        _ = Array(cached[start..<end])
        if end >= cached.count - 5 {
            Task { await self.loadMoreIfNeeded(feed: feed, currentCount: cached.count) }
        }
        return .loaded(cached)
    }

    func refresh(feed: FeedType) async -> LoadState<[CachedStory]> {
        let cached = persistence.fetchStories(for: feed)
        do {
            let ids = try await api.fetchStoryIDs(for: feed)
            persistence.updateCacheMetadata(feed: feed, ids: ids)
            loadedIDs[feed] = ids
            let firstPageIDs = Array(ids.prefix(pageSizeDefault))
            let dtos = try await api.fetchItems(ids: firstPageIDs, maxConcurrency: 8)
            for dto in dtos {
                if let existing = persistence.fetchCachedStory(id: dto.id) {
                    existing.update(from: dto, feed: feed)
                } else {
                    let story = CachedStory(from: dto, feed: feed)
                    persistence.context.insert(story)
                }
            }
            persistence.save()
            let updated = persistence.fetchStories(for: feed)
            logger.info("Refreshed \(feed.rawValue, privacy: .public): \(updated.count) stories")
            return .loaded(updated)
        } catch let err as APIError {
            logger.error("Refresh failed \(feed.rawValue, privacy: .public): \(err.localizedDescription, privacy: .public)")
            if !cached.isEmpty { return .failed(cached, err) }
            return .failed(nil, err)
        } catch {
            let apiErr = APIError.map(error)
            if !cached.isEmpty { return .failed(cached, apiErr) }
            return .failed(nil, apiErr)
        }
    }

    private func loadMoreIfNeeded(feed: FeedType, currentCount: Int) async {
        let ids = loadedIDs[feed] ?? persistence.fetchStories(for: feed).map(\.id)
        let nextPageIDs = Array(ids.dropFirst(currentCount).prefix(pageSizeDefault))
        guard !nextPageIDs.isEmpty else { return }
        do {
            let dtos = try await api.fetchItems(ids: nextPageIDs, maxConcurrency: 8)
            for dto in dtos {
                if let existing = persistence.fetchCachedStory(id: dto.id) {
                    existing.update(from: dto, feed: feed)
                } else {
                    persistence.context.insert(CachedStory(from: dto, feed: feed))
                }
            }
            persistence.save()
        } catch {
            logger.warning("Load more failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchStory(id: Int) async throws -> CachedStory {
        if let cached = persistence.fetchCachedStory(id: id) {
            if Date().timeIntervalSince(cached.lastFetchedAt) < CachePolicy.freshInterval {
                return cached
            }
        }
        do {
            let dto = try await api.fetchItem(id: id)
            if let existing = persistence.fetchCachedStory(id: dto.id) {
                existing.update(from: dto)
                persistence.save()
                return existing
            } else {
                let story = CachedStory(from: dto)
                persistence.context.insert(story)
                persistence.save()
                return story
            }
        } catch {
            if let cached = persistence.fetchCachedStory(id: id) { return cached }
            throw APIError.map(error)
        }
    }

    func toggleSave(storyID: Int) -> Bool {
        let currentlySaved = persistence.isSaved(storyID: storyID)
        if currentlySaved {
            persistence.unsaveStory(id: storyID)
            SoundManager.playUnsaveSound()
            HapticsManager.lightImpact()
            return false
        } else {
            if let story = persistence.fetchCachedStory(id: storyID) {
                persistence.saveStory(story)
            } else {
                let saved = SavedStory(storyID: storyID)
                persistence.context.insert(saved)
                persistence.save()
            }
            SoundManager.playSaveSound()
            HapticsManager.success()
            return true
        }
    }

    func isSaved(storyID: Int) -> Bool { persistence.isSaved(storyID: storyID) }

    func search(query: String) -> [CachedStory] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lower = query.lowercased()
        return persistence.fetchAllCachedStories().filter { story in
            story.title?.lowercased().contains(lower) == true ||
            story.author?.lowercased().contains(lower) == true ||
            story.domain?.lowercased().contains(lower) == true ||
            story.text?.lowercased().contains(lower) == true
        }
    }
}
