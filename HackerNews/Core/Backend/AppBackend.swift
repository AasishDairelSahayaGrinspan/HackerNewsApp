import Foundation
import Combine

/// Swift-native application backend.
///
/// The backend owns feeds, stories, comments, saved data, search and telemetry.
/// Views subscribe to immutable snapshots and send intents; they never perform
/// networking, persistence or cache-policy decisions themselves.
@MainActor
final class AppBackend: ObservableObject {
    static let shared = AppBackend()

    @Published private(set) var feed: FeedSnapshotModel = .idle
    @Published private(set) var storySnapshots: [Int: StorySnapshotModel] = [:]
    @Published private(set) var commentsSnapshots: [Int: CommentsSnapshotModel] = [:]
    @Published private(set) var savedStories: [SavedStory] = []
    @Published private(set) var status: EngineStatus = .empty

    let coreVersion = "Swift 6 · actor networking · SwiftData"

    private let api: any HackerNewsAPIProtocol
    private let persistence: PersistenceController
    private let searchIndex = SearchIndex()

    private var feedIDs: [FeedType: [Int]] = [:]
    private var loadedCounts: [FeedType: Int] = [:]
    private var currentFeed: FeedType = .top

    private var feedStories: [Story] = []
    private var feedPhase: LoadPhase = .idle
    private var feedError: EngineError?
    private var feedLastSync: Date?
    private var offline = false

    private var savedIDs: Set<Int> = []
    private var commentStoryKids: [Int: [Int]] = [:]
    private var commentGeneration: [Int: Int] = [:]

    private var feedTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var feedGeneration = 0
    private var storyTasks: [Int: Task<Void, Never>] = [:]
    private var commentTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    private var isRefreshing = false
    private var isLoadingMore = false
    private var startedAt: Date?
    private var revision: UInt64 = 0
    private var metrics = EngineMetrics()

    init(api: any HackerNewsAPIProtocol = HackerNewsAPI(),
         persistence: PersistenceController? = nil) {
        self.api = api
        self.persistence = persistence ?? .shared
    }

    // MARK: - Lifecycle

    func start() {
        guard startedAt == nil else { return }
        startedAt = Date()
        savedIDs = persistence.savedIDs()
        savedStories = persistence.fetchSavedStories().map(SavedStory.init)
        rebuildSearchIndex()
        loadCachedFeed(currentFeed)
        emitFeed()
        emitSaved()

        Task { await refreshStatus() }

        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                await self.refreshStatus()
            }
        }

        if needsRefresh(currentFeed) {
            refreshFeed()
        }
    }

    func shutdown() {
        feedTask?.cancel()
        loadMoreTask?.cancel()
        storyTasks.values.forEach { $0.cancel() }
        commentTask?.cancel()
        heartbeatTask?.cancel()
        storyTasks.removeAll()
        feedTask = nil
        loadMoreTask = nil
        commentTask = nil
        heartbeatTask = nil
        startedAt = nil
    }

    // MARK: - Feeds

    func selectFeed(_ feed: FeedType) {
        guard feed != currentFeed else {
            if needsRefresh(feed) { refreshFeed() }
            return
        }
        currentFeed = feed
        feedGeneration += 1
        feedTask?.cancel()
        loadMoreTask?.cancel()
        isRefreshing = false
        isLoadingMore = false
        loadCachedFeed(feed)
        emitFeed()
        if needsRefresh(feed) {
            refreshFeed()
        } else {
            Task { await refreshStatus() }
        }
    }

    func refreshFeed() {
        guard !isRefreshing else { return }
        isRefreshing = true
        feedGeneration += 1
        let generation = feedGeneration
        let feed = currentFeed
        feedPhase = feedStories.isEmpty ? .loading : .refreshing
        feedError = nil
        emitFeed()

        feedTask = Task { [weak self] in
            guard let self else { return }
            do {
                let ids = try await self.api.fetchStoryIDs(for: feed)
                try Task.checkCancellation()
                let firstPage = Array(ids.prefix(30))
                let dtos = try await self.api.fetchItems(ids: firstPage, maxConcurrency: 8)
                try Task.checkCancellation()
                guard feed == self.currentFeed, generation == self.feedGeneration else { return }

                let fetchedAt = Date()
                let stories = dtos.map {
                    Story($0, feed: feed, saved: self.savedIDs.contains($0.id), fetchedAt: fetchedAt)
                }
                self.persistence.upsertStories(stories)
                self.persistence.setFeedMeta(feed: feed, ids: ids, fetchedAt: fetchedAt)
                self.feedIDs[feed] = ids
                self.loadedCounts[feed] = firstPage.count
                for story in stories { self.searchIndex.upsert(story) }

                self.reloadFeedFromPersistence(feed)
                self.feedPhase = self.feedStories.isEmpty ? .failed : .loaded
                self.feedError = self.feedStories.isEmpty
                    ? EngineError(code: .unknown, message: "No stories available.", retryable: true)
                    : nil
                self.offline = false
                self.isRefreshing = false
                self.emitFeed()
                await self.refreshStatus()
            } catch {
                if Task.isCancelled { self.isRefreshing = false; return }
                guard feed == self.currentFeed, generation == self.feedGeneration else {
                    self.isRefreshing = false
                    return
                }
                let apiError = APIError.map(error)
                self.feedError = EngineError(apiError)
                self.feedPhase = self.feedStories.isEmpty ? .failed : .loaded
                if case .networkUnavailable = apiError { self.offline = true }
                self.isRefreshing = false
                self.emitFeed()
                await self.refreshStatus()
            }
        }
    }

    func loadMore() {
        guard !isRefreshing, !isLoadingMore else { return }
        let feed = currentFeed
        let ids = feedIDs[feed] ?? persistence.fetchFeedMeta(feed: feed)?.ids ?? []
        let start = loadedCounts[feed] ?? 0
        guard start < ids.count else { return }
        let end = min(start + 30, ids.count)
        let next = Array(ids[start..<end])
        guard !next.isEmpty else { return }

        isLoadingMore = true
        let requested = next.count
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let dtos = try await self.api.fetchItems(ids: next, maxConcurrency: 8)
                guard feed == self.currentFeed else {
                    self.isLoadingMore = false
                    return
                }
                let stories = dtos.map {
                    Story($0, feed: feed, saved: self.savedIDs.contains($0.id))
                }
                self.persistence.upsertStories(stories)
                for story in stories { self.searchIndex.upsert(story) }
                self.loadedCounts[feed] = start + requested
                self.reloadFeedFromPersistence(feed)
                self.isLoadingMore = false
                self.emitFeed()
                await self.refreshStatus()
            } catch {
                self.isLoadingMore = false
            }
        }
    }

    // MARK: - Stories

    func openStory(_ storyID: Int) {
        let cached = persistence.fetchStory(id: storyID)
        let story = cached.map { Story($0, saved: savedIDs.contains(storyID)) }

        if let story {
            if CachePolicy.isFresh(story.fetchedAt) {
                metrics.cacheHits += 1
                setStoryState(storyID, phase: .loaded, story: story, error: nil)
                return
            }
            metrics.cacheMisses += 1
            setStoryState(storyID, phase: .loading, story: story, error: nil)
        } else {
            metrics.cacheMisses += 1
            setStoryState(storyID, phase: .loading, story: nil, error: nil)
        }

        fetchStory(storyID, force: false)
    }

    func refreshStory(_ storyID: Int) {
        fetchStory(storyID, force: true)
    }

    private func fetchStory(_ storyID: Int, force: Bool) {
        if storyTasks[storyID] != nil { return }

        let cached = persistence.fetchStory(id: storyID)
        let current = cached.map { Story($0, saved: savedIDs.contains(storyID)) }

        if !force, let current, CachePolicy.isFresh(current.fetchedAt) {
            setStoryState(storyID, phase: .loaded, story: current, error: nil)
            return
        }

        setStoryState(storyID,
                      phase: current == nil ? .loading : .refreshing,
                      story: current,
                      error: nil)

        let feed = currentFeed
        storyTasks[storyID] = Task { [weak self] in
            guard let self else { return }
            do {
                let dto = try await self.api.fetchItem(id: storyID)
                try Task.checkCancellation()
                let story = Story(dto, feed: feed, saved: self.savedIDs.contains(storyID))
                self.persistence.upsertStories([story])
                self.searchIndex.upsert(story)
                self.offline = false
                self.setStoryState(storyID, phase: .loaded, story: story, error: nil)
                await self.refreshStatus()
            } catch {
                if Task.isCancelled {
                    self.storyTasks[storyID] = nil
                    return
                }
                let apiError = APIError.map(error)
                let fallback = self.persistence.fetchStory(id: storyID)
                    .map { Story($0, saved: self.savedIDs.contains(storyID)) }
                self.setStoryState(storyID,
                                   phase: fallback == nil ? .failed : .loaded,
                                   story: fallback,
                                   error: EngineError(apiError))
                if case .networkUnavailable = apiError { self.offline = true }
                await self.refreshStatus()
            }
            self.storyTasks[storyID] = nil
        }
    }

    // MARK: - Comments

    func loadComments(for storyID: Int, force: Bool) {
        commentGeneration[storyID, default: 0] += 1
        let generation = commentGeneration[storyID] ?? 0
        commentTask?.cancel()

        let cachedComments = persistence.fetchComments(storyID: storyID).map(Comment.init)
        let cachedStory = persistence.fetchStory(id: storyID)
        let kids = cachedStory?.kids ?? []
        commentStoryKids[storyID] = kids

        let roots = CommentTree.build(comments: cachedComments, rootKids: kids)
        let total = CommentTree.count(roots)
        let fresh = cachedStory.map { CachePolicy.isFresh($0.lastFetchedAt) } ?? false
        let shouldFetch = force || cachedComments.isEmpty || !fresh

        if !cachedComments.isEmpty && fresh {
            metrics.cacheHits += 1
        } else if cachedComments.isEmpty {
            metrics.cacheMisses += 1
        }

        setCommentsState(storyID,
                         roots: roots,
                         total: total,
                         loading: shouldFetch,
                         complete: !shouldFetch,
                         error: nil)

        guard shouldFetch else { return }

        if kids.isEmpty, let cachedStory, CachePolicy.isFresh(cachedStory.lastFetchedAt) {
            setCommentsState(storyID,
                             roots: roots,
                             total: total,
                             loading: false,
                             complete: true,
                             error: nil)
            return
        }

        if !kids.isEmpty {
            runCommentBFS(storyID: storyID, generation: generation, kids: kids, existingCount: cachedComments.count)
            return
        }

        commentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let dto = try await self.api.fetchItem(id: storyID)
                guard self.commentGeneration[storyID] == generation else { return }
                let story = Story(dto, feed: self.currentFeed, saved: self.savedIDs.contains(storyID))
                self.persistence.upsertStories([story])
                self.searchIndex.upsert(story)
                let kids = dto.kids ?? []
                self.commentStoryKids[storyID] = kids
                if kids.isEmpty {
                    self.emitComments(storyID: storyID, loading: false, complete: true, error: nil)
                    await self.refreshStatus()
                    return
                }
                self.runCommentBFS(storyID: storyID,
                                   generation: generation,
                                   kids: kids,
                                   existingCount: cachedComments.count)
            } catch {
                guard self.commentGeneration[storyID] == generation else { return }
                self.emitComments(storyID: storyID,
                                  loading: false,
                                  complete: true,
                                  error: EngineError(APIError.map(error)))
                await self.refreshStatus()
            }
        }
    }

    private func runCommentBFS(storyID: Int,
                               generation: Int,
                               kids: [Int],
                               existingCount: Int) {
        let maxDepth = 6
        let hardCap = 500
        let branchLimit = 30
        let chunkSize = 25

        commentTask = Task { [weak self] in
            guard let self else { return }
            var frontier = kids.uniqued()
            var seen = Set(frontier)
            var nextLevel: [Int] = []
            var depth = 0
            var total = existingCount

            while depth < maxDepth && total < hardCap {
                if Task.isCancelled { return }
                guard self.commentGeneration[storyID] == generation else { return }

                if frontier.isEmpty {
                    if nextLevel.isEmpty { break }
                    frontier = nextLevel
                    nextLevel.removeAll(keepingCapacity: true)
                    depth += 1
                    continue
                }

                let take = min(frontier.count, chunkSize, hardCap - total)
                guard take > 0 else { break }
                let chunk = Array(frontier.prefix(take))
                frontier.removeFirst(take)

                do {
                    let dtos = try await self.api.fetchItems(ids: chunk, maxConcurrency: 12)
                    guard !Task.isCancelled, self.commentGeneration[storyID] == generation else { return }

                    let fetchedAt = Date()
                    let comments = dtos.map { Comment($0, storyID: storyID, fetchedAt: fetchedAt) }
                    for comment in comments {
                        guard depth + 1 < maxDepth else { continue }
                        for kid in comment.kids.prefix(branchLimit) where seen.insert(kid).inserted {
                            nextLevel.append(kid)
                        }
                    }

                    if !comments.isEmpty {
                        self.persistence.upsertComments(comments)
                        self.metrics.commentsFetched += UInt64(comments.count)
                    }

                    total = self.persistence.fetchComments(storyID: storyID).count

                    if frontier.isEmpty {
                        frontier = nextLevel
                        nextLevel.removeAll(keepingCapacity: true)
                        depth += 1
                    }

                    self.emitComments(storyID: storyID, loading: true, complete: false, error: nil)
                    await self.refreshStatus()
                } catch {
                    if Task.isCancelled { return }
                    guard self.commentGeneration[storyID] == generation else { return }
                    self.emitComments(storyID: storyID,
                                      loading: false,
                                      complete: true,
                                      error: EngineError(APIError.map(error)))
                    await self.refreshStatus()
                    return
                }
            }

            guard self.commentGeneration[storyID] == generation else { return }
            self.emitComments(storyID: storyID, loading: false, complete: true, error: nil)
            await self.refreshStatus()
        }
    }

    // MARK: - Saved

    func toggleSave(_ storyID: Int) {
        setSaved(!savedIDs.contains(storyID), storyID: storyID)
    }

    func setSaved(_ saved: Bool, storyID: Int) {
        guard saved != savedIDs.contains(storyID) else {
            emitSaved()
            return
        }

        let stored = persistence.fetchStory(id: storyID).map {
            Story($0, saved: saved)
        } ?? storySnapshots[storyID]?.story
        persistence.setSaved(saved, storyID: storyID, story: stored)

        if saved {
            savedIDs.insert(storyID)
        } else {
            savedIDs.remove(storyID)
        }

        savedStories = persistence.fetchSavedStories().map(SavedStory.init)
        feedStories = feedStories.map { $0.withSaved(savedIDs.contains($0.id)) }

        if let snapshot = storySnapshots[storyID], let story = snapshot.story {
            revision += 1
            storySnapshots[storyID] = StorySnapshotModel(storyID: storyID,
                                                         revision: revision,
                                                         phase: snapshot.phase,
                                                         story: story.withSaved(saved),
                                                         error: snapshot.error)
            metrics.snapshotsEmitted += 1
        }

        emitSaved()
        emitFeed()
        Task { await refreshStatus() }
    }

    func isSaved(_ storyID: Int) -> Bool {
        savedIDs.contains(storyID)
    }

    func saved() -> [SavedStory] {
        persistence.fetchSavedStories().map(SavedStory.init)
    }

    // MARK: - Cache

    func clearCache(keepSaved: Bool) {
        feedGeneration += 1
        feedTask?.cancel()
        loadMoreTask?.cancel()
        storyTasks.values.forEach { $0.cancel() }
        commentTask?.cancel()
        storyTasks.removeAll()

        persistence.clear(keepSaved: keepSaved)
        savedIDs = persistence.savedIDs()
        savedStories = persistence.fetchSavedStories().map(SavedStory.init)
        rebuildSearchIndex()
        loadCachedFeed(currentFeed)
        feedPhase = feedStories.isEmpty ? .idle : .loaded
        feedError = nil
        emitFeed()
        emitSaved()
        Task { await refreshStatus() }

        if needsRefresh(currentFeed) {
            refreshFeed()
        }
    }

    func evictCache() {
        persistence.evict()
        rebuildSearchIndex()
        loadCachedFeed(currentFeed)
        emitFeed()
        Task { await refreshStatus() }
    }

    // MARK: - Search and reads

    func search(_ query: String, limit: Int = 100) -> [Story] {
        metrics.searchQueries += 1
        let ids = searchIndex.search(query, limit: limit)
        return persistence.fetchStories(ids: ids).map {
            Story($0, saved: savedIDs.contains($0.id))
        }
    }

    func currentStatus() -> EngineStatus { status }

    /// Async stream of feed snapshots used by pull-to-refresh waits.
    func feedUpdates() -> AsyncStream<FeedSnapshotModel> {
        AsyncStream { continuation in
            let cancellable = $feed.sink { continuation.yield($0) }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func storySnapshot(for storyID: Int) -> StorySnapshotModel? {
        storySnapshots[storyID]
    }

    func commentsSnapshot(for storyID: Int) -> CommentsSnapshotModel? {
        commentsSnapshots[storyID]
    }

    // MARK: - Private state

    private func loadCachedFeed(_ feed: FeedType) {
        feedStories = []
        feedError = nil
        feedPhase = .idle

        guard let meta = persistence.fetchFeedMeta(feed: feed), !meta.ids.isEmpty else {
            feedIDs[feed] = []
            loadedCounts[feed] = 0
            feedLastSync = nil
            return
        }

        feedIDs[feed] = meta.ids
        feedLastSync = meta.fetchedAt
        let cached = persistence.fetchStories(ids: meta.ids)
        feedStories = cached.map { Story($0, saved: savedIDs.contains($0.id)) }
        loadedCounts[feed] = feedStories.count
        feedPhase = feedStories.isEmpty ? .idle : .loaded
    }

    private func reloadFeedFromPersistence(_ feed: FeedType) {
        let ids = feedIDs[feed] ?? persistence.fetchFeedMeta(feed: feed)?.ids ?? []
        let cached = persistence.fetchStories(ids: ids)
        feedStories = cached.map { Story($0, saved: savedIDs.contains($0.id)) }
        feedLastSync = persistence.fetchFeedMeta(feed: feed)?.fetchedAt
    }

    private func needsRefresh(_ feed: FeedType) -> Bool {
        guard !feedStories.isEmpty, let last = feedLastSync else { return true }
        return CachePolicy.freshness(lastFetched: last) != .fresh
    }

    private func setStoryState(_ storyID: Int,
                               phase: LoadPhase,
                               story: Story?,
                               error: EngineError?) {
        revision += 1
        storySnapshots[storyID] = StorySnapshotModel(storyID: storyID,
                                                     revision: revision,
                                                     phase: phase,
                                                     story: story,
                                                     error: error)
        metrics.snapshotsEmitted += 1
    }

    private func setCommentsState(_ storyID: Int,
                                  roots: [CommentNode],
                                  total: Int,
                                  loading: Bool,
                                  complete: Bool,
                                  error: EngineError?) {
        revision += 1
        commentsSnapshots[storyID] = CommentsSnapshotModel(storyID: storyID,
                                                           revision: revision,
                                                           roots: roots,
                                                           totalLoaded: total,
                                                           loading: loading,
                                                           complete: complete,
                                                           error: error)
        metrics.snapshotsEmitted += 1
    }

    private func emitComments(storyID: Int,
                              loading: Bool,
                              complete: Bool,
                              error: EngineError?) {
        let comments = persistence.fetchComments(storyID: storyID).map(Comment.init)
        let kids = commentStoryKids[storyID] ?? persistence.fetchStory(id: storyID)?.kids ?? []
        let roots = CommentTree.build(comments: comments, rootKids: kids)
        setCommentsState(storyID,
                         roots: roots,
                         total: CommentTree.count(roots),
                         loading: loading,
                         complete: complete,
                         error: error)
    }

    private func emitFeed() {
        revision += 1
        let stale = feedLastSync.map {
            CachePolicy.freshness(lastFetched: $0) != .fresh
        } ?? false
        feed = FeedSnapshotModel(feed: currentFeed,
                                 revision: revision,
                                 phase: feedPhase,
                                 stories: feedStories,
                                 lastSyncAt: feedLastSync,
                                 offline: offline,
                                 stale: stale,
                                 error: feedError)
        metrics.snapshotsEmitted += 1
    }

    private func emitSaved() {
        revision += 1
        savedStories = persistence.fetchSavedStories().map(SavedStory.init)
        metrics.snapshotsEmitted += 1
    }

    private func rebuildSearchIndex() {
        searchIndex.clear()
        for cached in persistence.fetchAllStories() {
            searchIndex.upsert(Story(cached, saved: savedIDs.contains(cached.id)))
        }
    }

    private func refreshStatus() async {
        let apiMetrics = await api.metrics()
        var combined = metrics
        combined.apply(apiMetrics)

        var snapshot = EngineStatus()
        snapshot.revision = revision
        snapshot.feed = currentFeed
        snapshot.phase = feedPhase
        snapshot.offline = offline
        snapshot.lastSyncAt = feedLastSync
        snapshot.cachedStories = persistence.countStories()
        snapshot.cachedComments = persistence.countComments()
        snapshot.savedCount = persistence.countSaved()
        snapshot.searchDocs = searchIndex.count
        snapshot.databaseBytes = persistence.databaseBytes()
        snapshot.uptimeSeconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        snapshot.coreVersion = coreVersion
        snapshot.metrics = combined
        status = snapshot
    }
}
