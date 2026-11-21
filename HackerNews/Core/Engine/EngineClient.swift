import Foundation
import Combine

/// Thin Swift adapter over the Objective-C++ bridge.
///
/// The C++ engine owns networking, persistence, caching, comment traversal,
/// search and telemetry. This object only mirrors the latest snapshots into
/// Combine publishers and forwards user intents as engine commands.
final class EngineClient: NSObject, ObservableObject {
    static let shared = EngineClient()

    static let baseURL = "https://hacker-news.firebaseio.com/v0/"

    @Published private(set) var feed: FeedSnapshotModel = .idle
    @Published private(set) var storySnapshots: [Int: StorySnapshotModel] = [:]
    @Published private(set) var commentsSnapshots: [Int: CommentsSnapshotModel] = [:]
    @Published private(set) var savedStories: [SavedStory] = []
    @Published private(set) var status: EngineStatus = .empty

    let engine: HNEngine
    private var started = false

    override convenience init() {
        self.init(databasePath: Self.defaultDatabasePath(), baseURL: Self.baseURL)
    }

    init(databasePath: String, baseURL: String) {
        engine = HNEngine(databasePath: databasePath, baseURL: baseURL)
        super.init()
        engine.listener = self
    }

    deinit {
        engine.shutdown()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        engine.start()
    }

    func shutdown() {
        guard started else { return }
        started = false
        engine.shutdown()
    }

    // MARK: - Commands

    func selectFeed(_ feed: FeedType) {
        engine.selectFeed(feed.bridgeValue)
    }

    func refreshFeed() {
        engine.refreshFeed()
    }

    func loadMore() {
        engine.loadMore()
    }

    func openStory(_ storyID: Int) {
        engine.openStory(storyID)
    }

    func refreshStory(_ storyID: Int) {
        engine.refreshStory(storyID)
    }

    func loadComments(for storyID: Int, force: Bool) {
        engine.loadComments(forStory: storyID, force: force)
    }

    func toggleSave(_ storyID: Int) {
        engine.toggleSave(storyID)
    }

    func setSaved(_ saved: Bool, storyID: Int) {
        engine.setSaved(saved, storyID: storyID)
    }

    func isSaved(_ storyID: Int) -> Bool {
        engine.isSaved(storyID)
    }

    func clearCache(keepSaved: Bool) {
        engine.clearCache(keepSaved: keepSaved)
    }

    func evictCache() {
        engine.evictCache()
    }

    // MARK: - Synchronous reads

    func search(_ query: String, limit: Int = 100) -> [Story] {
        engine.search(query, limit: limit).map(Story.init)
    }

    func saved() -> [SavedStory] {
        engine.savedStories().map(SavedStory.init)
    }

    func currentStatus() -> EngineStatus {
        EngineStatus(engine.status())
    }

    func storySnapshot(for storyID: Int) -> StorySnapshotModel? {
        storySnapshots[storyID]
    }

    func commentsSnapshot(for storyID: Int) -> CommentsSnapshotModel? {
        commentsSnapshots[storyID]
    }

    var coreVersion: String {
        engine.coreVersion()
    }

    // MARK: - Paths

    private static func defaultDatabasePath() -> String {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("HackerNews", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("engine.sqlite").path
    }

    // MARK: - Snapshot application

    private func applyOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - HNEngineListener

extension EngineClient: HNEngineListener {
    func engine(_ engine: HNEngine, didUpdateFeed snapshot: HNFeedSnapshot) {
        let model = FeedSnapshotModel(snapshot)
        applyOnMain { [weak self] in
            guard let self else { return }
            self.feed = model
        }
    }

    func engine(_ engine: HNEngine, didUpdateStory snapshot: HNStorySnapshot) {
        let model = StorySnapshotModel(snapshot)
        applyOnMain { [weak self] in
            guard let self else { return }
            self.storySnapshots[model.storyID] = model
        }
    }

    func engine(_ engine: HNEngine, didUpdateComments snapshot: HNCommentsSnapshot) {
        let model = CommentsSnapshotModel(snapshot)
        applyOnMain { [weak self] in
            guard let self else { return }
            self.commentsSnapshots[model.storyID] = model
        }
    }

    func engine(_ engine: HNEngine, didUpdateSaved snapshot: HNSavedSnapshot) {
        let stories = snapshot.stories.map(SavedStory.init)
        applyOnMain { [weak self] in
            guard let self else { return }
            self.savedStories = stories
        }
    }

    func engine(_ engine: HNEngine, didUpdateStatus status: HNStatus) {
        let model = EngineStatus(status)
        applyOnMain { [weak self] in
            guard let self else { return }
            self.status = model
        }
    }
}
