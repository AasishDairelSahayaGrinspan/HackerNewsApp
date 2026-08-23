import Foundation
import SwiftData
import os

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private let logger = Logger(subsystem: "com.hacknews.app", category: "persistence")

    init(inMemory: Bool = false) {
        let schema = Schema([CachedStory.self, CachedComment.self, SavedStory.self, CacheMetadata.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Save helper
    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - CachedStory helpers
    func fetchCachedStory(id: Int) -> CachedStory? {
        let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func fetchAllCachedStories() -> [CachedStory] {
        let descriptor = FetchDescriptor<CachedStory>(sortBy: [SortDescriptor(\.lastFetchedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchStories(for feed: FeedType) -> [CachedStory] {
        let raw = feed.rawValue
        let metaDescriptor = FetchDescriptor<CacheMetadata>(predicate: #Predicate { $0.feedTypeRaw == raw })
        guard let meta = try? context.fetch(metaDescriptor).first, !meta.storyIDs.isEmpty else {
            let all = fetchAllCachedStories().filter { $0.feedTypeRaw == raw }
            return all
        }
        var map: [Int: CachedStory] = [:]
        for s in fetchAllCachedStories() { map[s.id] = s }
        return meta.storyIDs.compactMap { map[$0] }
    }

    // MARK: - Saved
    func isSaved(storyID: Int) -> Bool {
        let descriptor = FetchDescriptor<SavedStory>(predicate: #Predicate { $0.storyID == storyID })
        return (try? context.fetch(descriptor).first) != nil
    }

    func fetchSavedStories() -> [SavedStory] {
        let descriptor = FetchDescriptor<SavedStory>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func saveStory(_ story: CachedStory) {
        if isSaved(storyID: story.id) { return }
        let saved = SavedStory(storyID: story.id, title: story.title, author: story.author, url: story.url, score: story.score)
        context.insert(saved)
        save()
    }

    func unsaveStory(id: Int) {
        let descriptor = FetchDescriptor<SavedStory>(predicate: #Predicate { $0.storyID == id })
        if let found = try? context.fetch(descriptor).first {
            context.delete(found)
            save()
        }
    }

    // MARK: - CacheMetadata
    func updateCacheMetadata(feed: FeedType, ids: [Int]) {
        let raw = feed.rawValue
        let descriptor = FetchDescriptor<CacheMetadata>(predicate: #Predicate { $0.feedTypeRaw == raw })
        if let existing = try? context.fetch(descriptor).first {
            existing.storyIDs = ids
            existing.lastFetchedAt = Date()
        } else {
            let meta = CacheMetadata(feedTypeRaw: raw, lastFetchedAt: Date(), storyIDs: ids)
            context.insert(meta)
        }
        save()
    }

    func lastFetched(for feed: FeedType) -> Date? {
        let raw = feed.rawValue
        let descriptor = FetchDescriptor<CacheMetadata>(predicate: #Predicate { $0.feedTypeRaw == raw })
        return try? context.fetch(descriptor).first?.lastFetchedAt
    }

    // MARK: - Comments
    func fetchComments(for storyID: Int) -> [CachedComment] {
        let descriptor = FetchDescriptor<CachedComment>(predicate: #Predicate { $0.storyID == storyID })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Cache Eviction
    /// Keeps saved + recent. Policy documented here.
    func evictExpiredCache(maxFeedItems: Int = 200, maxAge: TimeInterval = 60*60*24*3) {
        // Don't evict saved stories
        let savedIDs = Set(fetchSavedStories().map(\.storyID))
        let all = fetchAllCachedStories()
        let cutoff = Date().addingTimeInterval(-maxAge)

        // Sort by lastFetchedAt, keep most recent up to limit per feed?
        // Simplified: keep stories that are either saved, or recently fetched, or within metadata
        var metadataIDs = Set<Int>()
        let metaDescriptor = FetchDescriptor<CacheMetadata>()
        if let metas = try? context.fetch(metaDescriptor) {
            for m in metas { metadataIDs.formUnion(m.storyIDs.prefix(maxFeedItems)) }
        }

        for story in all {
            if savedIDs.contains(story.id) { continue }
            if metadataIDs.contains(story.id) { continue }
            if story.lastFetchedAt > cutoff { continue }
            context.delete(story)
        }

        // Evict old comments for evicted stories
        // Keep comments for saved stories
        let comments = (try? context.fetch(FetchDescriptor<CachedComment>())) ?? []
        for c in comments {
            if savedIDs.contains(c.storyID) { continue }
            if metadataIDs.contains(c.storyID) { continue }
            // If story no longer exists, delete comment
            if fetchCachedStory(id: c.storyID) == nil {
                context.delete(c)
            }
        }
        save()
        logger.info("Cache eviction completed. Kept \(metadataIDs.count) feed items, \(savedIDs.count) saved.")
    }

    func clearAllCache(keepSaved: Bool = true) {
        let savedIDs = keepSaved ? Set(fetchSavedStories().map(\.storyID)) : Set<Int>()
        for story in fetchAllCachedStories() where !savedIDs.contains(story.id) {
            context.delete(story)
        }
        if !keepSaved {
            for s in fetchSavedStories() { context.delete(s) }
        }
        let metas = (try? context.fetch(FetchDescriptor<CacheMetadata>())) ?? []
        for m in metas { context.delete(m) }
        let comments = (try? context.fetch(FetchDescriptor<CachedComment>())) ?? []
        for c in comments where !savedIDs.contains(c.storyID) { context.delete(c) }
        save()
    }
}
