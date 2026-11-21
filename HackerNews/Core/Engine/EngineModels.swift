import Foundation

// MARK: - Presentation models

/// A story as rendered by SwiftUI. Every field is produced by the C++ engine;
/// Swift never parses JSON or touches the network.
struct Story: Identifiable, Hashable {
    let id: Int
    let title: String?
    let author: String?
    let url: String?
    let text: String?
    let plainText: String
    let domain: String?
    let timeAgo: String
    let score: Int
    let commentCount: Int
    let createdAt: Date?
    let isDead: Bool
    let isHnDeleted: Bool
    let isSaved: Bool
    let feed: FeedType

    init(_ object: HNStory) {
        id = object.storyID
        title = object.title
        author = object.author
        url = object.url
        text = object.text
        plainText = object.plainText
        domain = object.domain
        timeAgo = object.timeAgo
        score = object.score
        commentCount = object.commentCount
        createdAt = object.createdAt
        isDead = object.isDead
        isHnDeleted = object.isDeleted
        isSaved = object.isSaved
        feed = FeedType(object.feed)
    }

    init(id: Int,
         title: String?,
         author: String? = nil,
         url: String? = nil,
         text: String? = nil,
         plainText: String = "",
         domain: String? = nil,
         timeAgo: String = "",
         score: Int = 0,
         commentCount: Int = 0,
         createdAt: Date? = nil,
         isDead: Bool = false,
         isHnDeleted: Bool = false,
         isSaved: Bool = false,
         feed: FeedType = .top) {
        self.id = id
        self.title = title
        self.author = author
        self.url = url
        self.text = text
        self.plainText = plainText
        self.domain = domain
        self.timeAgo = timeAgo
        self.score = score
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.isDead = isDead
        self.isHnDeleted = isHnDeleted
        self.isSaved = isSaved
        self.feed = feed
    }

    func withSaved(_ saved: Bool) -> Story {
        Story(id: id,
              title: title,
              author: author,
              url: url,
              text: text,
              plainText: plainText,
              domain: domain,
              timeAgo: timeAgo,
              score: score,
              commentCount: commentCount,
              createdAt: createdAt,
              isDead: isDead,
              isHnDeleted: isHnDeleted,
              isSaved: saved,
              feed: feed)
    }
}

/// A flattened comment tree node. Collapse state is purely a presentation
/// concern and stays in Swift.
struct CommentNode: Identifiable, Hashable {
    let id: Int
    let parentID: Int
    let author: String?
    let text: String?
    let plainText: String
    let createdAt: Date?
    let timeAgo: String
    let isDead: Bool
    let isHnDeleted: Bool
    let depth: Int
    var children: [CommentNode]
    var isCollapsed: Bool = false

    init(_ object: HNComment) {
        id = object.commentID
        parentID = object.parentID
        author = object.author
        text = object.text
        plainText = object.plainText
        createdAt = object.createdAt
        timeAgo = object.timeAgo
        isDead = object.isDead
        isHnDeleted = object.isDeleted
        depth = object.depth
        children = object.children.map(CommentNode.init)
        isCollapsed = false
    }

    func applyingCollapsed(_ collapsed: Set<Int>) -> CommentNode {
        var copy = self
        copy.isCollapsed = collapsed.contains(id)
        copy.children = children.map { $0.applyingCollapsed(collapsed) }
        return copy
    }

    func collectCollapsed(into set: inout Set<Int>) {
        if isCollapsed { set.insert(id) }
        for child in children { child.collectCollapsed(into: &set) }
    }

    func collectingIDs(into set: inout Set<Int>) {
        set.insert(id)
        for child in children { child.collectingIDs(into: &set) }
    }
}

struct SavedStory: Identifiable, Hashable {
    var id: Int { storyID }
    let storyID: Int
    let savedAt: Date
    let title: String?
    let author: String?
    let url: String?
    let domain: String?
    let score: Int

    init(_ object: HNSavedStory) {
        storyID = object.storyID
        savedAt = object.savedAt
        title = object.title
        author = object.author
        url = object.url
        domain = object.domain
        score = object.score
    }
}

// MARK: - Snapshots

struct EngineError: Hashable {
    let code: HNErrorCode
    let httpStatus: Int
    let message: String
    let retryable: Bool

    init(_ object: HNError) {
        code = object.code
        httpStatus = object.httpStatus
        message = object.message
        retryable = object.retryable
    }
}

struct FeedSnapshotModel {
    let feed: FeedType
    let revision: UInt64
    let phase: HNPhase
    let stories: [Story]
    let lastSyncAt: Date?
    let offline: Bool
    let stale: Bool
    let error: EngineError?

    init(_ snapshot: HNFeedSnapshot) {
        feed = FeedType(snapshot.feed)
        revision = snapshot.revision
        phase = snapshot.phase
        stories = snapshot.stories.map(Story.init)
        lastSyncAt = snapshot.lastSyncAt
        offline = snapshot.offline
        stale = snapshot.stale
        error = snapshot.error.map(EngineError.init)
    }

    static let idle = FeedSnapshotModel(feed: .top,
                                        revision: 0,
                                        phase: .idle,
                                        stories: [],
                                        lastSyncAt: nil,
                                        offline: false,
                                        stale: false,
                                        error: nil)

    init(feed: FeedType,
         revision: UInt64,
         phase: HNPhase,
         stories: [Story],
         lastSyncAt: Date?,
         offline: Bool,
         stale: Bool,
         error: EngineError?) {
        self.feed = feed
        self.revision = revision
        self.phase = phase
        self.stories = stories
        self.lastSyncAt = lastSyncAt
        self.offline = offline
        self.stale = stale
        self.error = error
    }
}

struct StorySnapshotModel {
    let storyID: Int
    let revision: UInt64
    let phase: HNPhase
    let story: Story?
    let error: EngineError?

    init(_ snapshot: HNStorySnapshot) {
        storyID = snapshot.storyID
        revision = snapshot.revision
        phase = snapshot.phase
        story = snapshot.story.map(Story.init)
        error = snapshot.error.map(EngineError.init)
    }
}

struct CommentsSnapshotModel {
    let storyID: Int
    let revision: UInt64
    let roots: [CommentNode]
    let totalLoaded: Int
    let loading: Bool
    let complete: Bool
    let error: EngineError?

    init(_ snapshot: HNCommentsSnapshot) {
        storyID = snapshot.storyID
        revision = snapshot.revision
        roots = snapshot.roots.map(CommentNode.init)
        totalLoaded = snapshot.totalLoaded
        loading = snapshot.loading
        complete = snapshot.complete
        error = snapshot.error.map(EngineError.init)
    }

    static func empty(storyID: Int) -> CommentsSnapshotModel {
        CommentsSnapshotModel(storyID: storyID,
                              revision: 0,
                              roots: [],
                              totalLoaded: 0,
                              loading: false,
                              complete: false,
                              error: nil)
    }

    init(storyID: Int,
         revision: UInt64,
         roots: [CommentNode],
         totalLoaded: Int,
         loading: Bool,
         complete: Bool,
         error: EngineError?) {
        self.storyID = storyID
        self.revision = revision
        self.roots = roots
        self.totalLoaded = totalLoaded
        self.loading = loading
        self.complete = complete
        self.error = error
    }
}

// MARK: - Telemetry

struct EngineMetrics: Hashable {
    let requests: UInt64
    let failures: UInt64
    let retries: UInt64
    let bytesReceived: UInt64
    let itemsParsed: UInt64
    let cacheHits: UInt64
    let cacheMisses: UInt64
    let snapshotsEmitted: UInt64
    let commentsFetched: UInt64
    let searchQueries: UInt64
    let inFlight: Int
    let lastLatencyMs: Double
    let averageLatencyMs: Double

    init(_ metrics: HNMetrics) {
        requests = metrics.requests
        failures = metrics.failures
        retries = metrics.retries
        bytesReceived = metrics.bytesReceived
        itemsParsed = metrics.itemsParsed
        cacheHits = metrics.cacheHits
        cacheMisses = metrics.cacheMisses
        snapshotsEmitted = metrics.snapshotsEmitted
        commentsFetched = metrics.commentsFetched
        searchQueries = metrics.searchQueries
        inFlight = metrics.inFlight
        lastLatencyMs = metrics.lastLatencyMs
        averageLatencyMs = metrics.averageLatencyMs
    }

    static let empty = EngineMetrics(requests: 0,
                                     failures: 0,
                                     retries: 0,
                                     bytesReceived: 0,
                                     itemsParsed: 0,
                                     cacheHits: 0,
                                     cacheMisses: 0,
                                     snapshotsEmitted: 0,
                                     commentsFetched: 0,
                                     searchQueries: 0,
                                     inFlight: 0,
                                     lastLatencyMs: 0,
                                     averageLatencyMs: 0)

    init(requests: UInt64,
         failures: UInt64,
         retries: UInt64,
         bytesReceived: UInt64,
         itemsParsed: UInt64,
         cacheHits: UInt64,
         cacheMisses: UInt64,
         snapshotsEmitted: UInt64,
         commentsFetched: UInt64,
         searchQueries: UInt64,
         inFlight: Int,
         lastLatencyMs: Double,
         averageLatencyMs: Double) {
        self.requests = requests
        self.failures = failures
        self.retries = retries
        self.bytesReceived = bytesReceived
        self.itemsParsed = itemsParsed
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
        self.snapshotsEmitted = snapshotsEmitted
        self.commentsFetched = commentsFetched
        self.searchQueries = searchQueries
        self.inFlight = inFlight
        self.lastLatencyMs = lastLatencyMs
        self.averageLatencyMs = averageLatencyMs
    }

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total == 0 ? 0 : Double(cacheHits) / Double(total)
    }
}

struct EngineStatus: Hashable {
    let revision: UInt64
    let feed: FeedType
    let phase: HNPhase
    let offline: Bool
    let lastSyncAt: Date?
    let cachedStories: Int
    let cachedComments: Int
    let savedCount: Int
    let searchDocs: Int
    let databaseBytes: Int64
    let uptimeSeconds: TimeInterval
    let coreVersion: String
    let metrics: EngineMetrics

    init(_ status: HNStatus) {
        revision = status.revision
        feed = FeedType(status.feed)
        phase = status.phase
        offline = status.offline
        lastSyncAt = status.lastSyncAt
        cachedStories = status.cachedStories
        cachedComments = status.cachedComments
        savedCount = status.savedCount
        searchDocs = status.searchDocs
        databaseBytes = status.databaseBytes
        uptimeSeconds = status.uptimeSeconds
        coreVersion = status.coreVersion
        metrics = EngineMetrics(status.metrics)
    }

    init(revision: UInt64,
         feed: FeedType,
         phase: HNPhase,
         offline: Bool,
         lastSyncAt: Date?,
         cachedStories: Int,
         cachedComments: Int,
         savedCount: Int,
         searchDocs: Int,
         databaseBytes: Int64,
         uptimeSeconds: TimeInterval,
         coreVersion: String,
         metrics: EngineMetrics) {
        self.revision = revision
        self.feed = feed
        self.phase = phase
        self.offline = offline
        self.lastSyncAt = lastSyncAt
        self.cachedStories = cachedStories
        self.cachedComments = cachedComments
        self.savedCount = savedCount
        self.searchDocs = searchDocs
        self.databaseBytes = databaseBytes
        self.uptimeSeconds = uptimeSeconds
        self.coreVersion = coreVersion
        self.metrics = metrics
    }

    static let empty = EngineStatus(revision: 0,
                                    feed: .top,
                                    phase: .idle,
                                    offline: false,
                                    lastSyncAt: nil,
                                    cachedStories: 0,
                                    cachedComments: 0,
                                    savedCount: 0,
                                    searchDocs: 0,
                                    databaseBytes: 0,
                                    uptimeSeconds: 0,
                                    coreVersion: "HNCore",
                                    metrics: .empty)

    var formattedDatabaseSize: String {
        ByteCountFormatter.string(fromByteCount: databaseBytes, countStyle: .file)
    }
}
