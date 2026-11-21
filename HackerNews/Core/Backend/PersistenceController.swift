import Foundation
import SwiftData
import os

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private let isInMemory: Bool
    private let logger = Logger(subsystem: "com.hacknews.app", category: "persistence")

    init(inMemory: Bool = false) {
        let schema = Schema([
            CachedStory.self,
            CachedComment.self,
            SavedStoryModel.self,
            CacheMetadata.self
        ])
        let configuration = ModelConfiguration(schema: schema,
                                              isStoredInMemoryOnly: inMemory,
                                              allowsSave: true)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            isInMemory = inMemory
        } catch {
            logger.error("ModelContainer failed: \(error.localizedDescription, privacy: .public)")

            // An older build can leave a store whose schema no longer matches
            // (for example a newly added non-optional field). Cache data is
            // disposable, so rebuild the store instead of degrading to memory.
            if !inMemory {
                Self.removeStore(at: configuration.url)
                do {
                    container = try ModelContainer(for: schema, configurations: [configuration])
                    isInMemory = false
                    logger.info("Recreated the local store after a schema mismatch")
                    return
                } catch {
                    logger.error("Store rebuild failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            logger.error("Falling back to an in-memory store")
            let fallback = ModelConfiguration(schema: schema,
                                              isStoredInMemoryOnly: true,
                                              allowsSave: true)
            container = try! ModelContainer(for: schema, configurations: [fallback])
            isInMemory = true
        }
    }

    private static func removeStore(at url: URL) {
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? manager.removeItem(atPath: url.path + suffix)
        }
    }

    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Stories

    func fetchStory(id: Int) -> CachedStory? {
        let descriptor = FetchDescriptor<CachedStory>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func fetchAllStories() -> [CachedStory] {
        let descriptor = FetchDescriptor<CachedStory>(
            sortBy: [SortDescriptor(\.lastFetchedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchStories(ids: [Int]) -> [CachedStory] {
        guard !ids.isEmpty else { return [] }
        let map = Dictionary(uniqueKeysWithValues: fetchAllStories().map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

    func fetchStories(for feed: FeedType) -> [CachedStory] {
        guard let meta = fetchFeedMeta(feed: feed), !meta.ids.isEmpty else {
            return fetchAllStories().filter { $0.feedTypeRaw == feed.rawValue }
        }
        let ordered = fetchStories(ids: meta.ids)
        if ordered.isEmpty {
            return fetchAllStories().filter { $0.feedTypeRaw == feed.rawValue }
        }
        return ordered
    }

    func upsertStories(_ stories: [Story]) {
        guard !stories.isEmpty else { return }
        for story in stories {
            if let existing = fetchStory(id: story.id) {
                existing.update(from: story)
            } else {
                context.insert(CachedStory(from: story))
            }
        }
        save()
    }

    func update(story: Story) {
        upsertStories([story])
    }

    // MARK: - Feed metadata

    func fetchFeedMeta(feed: FeedType) -> (ids: [Int], fetchedAt: Date?)? {
        let raw = feed.rawValue
        let descriptor = FetchDescriptor<CacheMetadata>(predicate: #Predicate { $0.feedTypeRaw == raw })
        guard let meta = try? context.fetch(descriptor).first else { return nil }
        return (meta.storyIDs, meta.lastFetchedAt)
    }

    func setFeedMeta(feed: FeedType, ids: [Int], fetchedAt: Date = Date()) {
        let raw = feed.rawValue
        let descriptor = FetchDescriptor<CacheMetadata>(predicate: #Predicate { $0.feedTypeRaw == raw })
        if let existing = try? context.fetch(descriptor).first {
            existing.storyIDs = ids
            existing.lastFetchedAt = fetchedAt
        } else {
            context.insert(CacheMetadata(feedTypeRaw: raw, lastFetchedAt: fetchedAt, storyIDs: ids))
        }
        save()
    }

    // MARK: - Comments

    func fetchComments(storyID: Int) -> [CachedComment] {
        let descriptor = FetchDescriptor<CachedComment>(predicate: #Predicate { $0.storyID == storyID })
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchComments(storyIDs: Set<Int>) -> [CachedComment] {
        var result: [CachedComment] = []
        for id in storyIDs { result.append(contentsOf: fetchComments(storyID: id)) }
        return result
    }

    func upsertComments(_ comments: [Comment]) {
        guard !comments.isEmpty else { return }
        let existing = fetchComments(storyIDs: Set(comments.map(\.storyID)))
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for comment in comments {
            if let cached = map[comment.id] {
                cached.update(from: comment)
            } else {
                context.insert(CachedComment(from: comment))
            }
        }
        save()
    }

    // MARK: - Saved

    func isSaved(storyID: Int) -> Bool {
        let descriptor = FetchDescriptor<SavedStoryModel>(predicate: #Predicate { $0.storyID == storyID })
        return (try? context.fetch(descriptor).first) != nil
    }

    func savedIDs() -> Set<Int> {
        let saved = fetchSavedStories()
        return Set(saved.map(\.storyID))
    }

    func fetchSavedStories() -> [SavedStoryModel] {
        let descriptor = FetchDescriptor<SavedStoryModel>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func setSaved(_ saved: Bool, storyID: Int, story: Story?) {
        let descriptor = FetchDescriptor<SavedStoryModel>(predicate: #Predicate { $0.storyID == storyID })
        let existing = try? context.fetch(descriptor).first

        if !saved {
            if let existing { context.delete(existing) }
            save()
            return
        }

        if let existing {
            if let story {
                existing.title = story.title ?? existing.title
                existing.author = story.author ?? existing.author
                existing.url = story.url ?? existing.url
                if story.score != 0 { existing.score = story.score }
            }
        } else {
            context.insert(SavedStoryModel(storyID: storyID,
                                           title: story?.title,
                                           author: story?.author,
                                           url: story?.url,
                                           score: story?.score ?? 0))
        }
        save()
    }

    // MARK: - Counts

    func countStories() -> Int {
        (try? context.fetchCount(FetchDescriptor<CachedStory>())) ?? 0
    }

    func countComments() -> Int {
        (try? context.fetchCount(FetchDescriptor<CachedComment>())) ?? 0
    }

    func countSaved() -> Int {
        (try? context.fetchCount(FetchDescriptor<SavedStoryModel>())) ?? 0
    }

    func databaseBytes() -> Int64 {
        guard !isInMemory,
              let url = container.configurations.first?.url,
              url.path != "/dev/null" else { return 0 }
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    // MARK: - Eviction

    func evict(maxFeedItems: Int = CachePolicy.evictionFeedItems,
               maxAge: TimeInterval = CachePolicy.evictionAge) {
        let saved = savedIDs()
        let cutoff = Date().addingTimeInterval(-maxAge)

        var metadataIDs = Set<Int>()
        if let metas = try? context.fetch(FetchDescriptor<CacheMetadata>()) {
            for meta in metas {
                metadataIDs.formUnion(meta.storyIDs.prefix(maxFeedItems))
            }
        }

        let allStories = fetchAllStories()
        for story in allStories {
            if saved.contains(story.id) { continue }
            if metadataIDs.contains(story.id) { continue }
            if story.lastFetchedAt > cutoff { continue }
            context.delete(story)
        }

        let comments = (try? context.fetch(FetchDescriptor<CachedComment>())) ?? []
        for comment in comments {
            if saved.contains(comment.storyID) { continue }
            if metadataIDs.contains(comment.storyID) { continue }
            if fetchStory(id: comment.storyID) == nil {
                context.delete(comment)
            }
        }

        save()
        logger.info("Cache eviction kept \(metadataIDs.count) feed items and \(saved.count) saved stories")
    }

    func clear(keepSaved: Bool) {
        let saved = keepSaved ? savedIDs() : []

        for story in fetchAllStories() where !saved.contains(story.id) {
            context.delete(story)
        }

        if !keepSaved {
            for model in fetchSavedStories() { context.delete(model) }
        }

        if let metas = try? context.fetch(FetchDescriptor<CacheMetadata>()) {
            for meta in metas { context.delete(meta) }
        }

        let comments = (try? context.fetch(FetchDescriptor<CachedComment>())) ?? []
        for comment in comments where !saved.contains(comment.storyID) {
            context.delete(comment)
        }

        save()
    }
}
