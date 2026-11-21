import Foundation

// MARK: - Lifecycle

enum LoadPhase: Int, Equatable, Sendable {
    case idle
    case loading
    case refreshing
    case loaded
    case failed

    var isLoading: Bool { self == .loading || self == .refreshing }
}

// MARK: - Story

/// A story as rendered by SwiftUI. Produced by the Swift backend from the HN
/// wire item and the local SwiftData store.
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
    let kids: [Int]
    let fetchedAt: Date

    init(_ dto: HNItemDTO,
         feed: FeedType,
         saved: Bool = false,
         fetchedAt: Date = Date()) {
        id = dto.id
        title = dto.title
        author = dto.by
        url = dto.url
        text = dto.text
        plainText = dto.text?.strippedHTML ?? ""
        domain = dto.domain
        createdAt = dto.createdDate
        timeAgo = dto.createdDate?.timeAgoDisplay() ?? "unknown"
        score = dto.score ?? 0
        commentCount = dto.descendants ?? dto.kids?.count ?? 0
        isDead = dto.isDead
        isHnDeleted = dto.isDeleted
        isSaved = saved
        self.feed = feed
        kids = dto.kids ?? []
        self.fetchedAt = fetchedAt
    }

    init(_ cached: CachedStory, saved: Bool) {
        id = cached.id
        title = cached.title
        author = cached.author
        url = cached.url
        text = cached.text
        plainText = cached.text?.strippedHTML ?? ""
        domain = cached.domain
        createdAt = cached.createdAt
        timeAgo = cached.createdAt?.timeAgoDisplay() ?? "unknown"
        score = cached.score
        commentCount = cached.commentCount
        isDead = cached.isDead
        isHnDeleted = cached.isHnDeleted
        isSaved = saved
        feed = FeedType(rawValue: cached.feedTypeRaw ?? "") ?? .top
        kids = cached.kids
        fetchedAt = cached.lastFetchedAt
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
         feed: FeedType = .top,
         kids: [Int] = [],
         fetchedAt: Date = Date()) {
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
        self.kids = kids
        self.fetchedAt = fetchedAt
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
              feed: feed,
              kids: kids,
              fetchedAt: fetchedAt)
    }
}

// MARK: - Comment

struct Comment: Identifiable, Hashable {
    let id: Int
    let storyID: Int
    let parentID: Int?
    let author: String?
    let text: String?
    let plainText: String
    let createdAt: Date?
    let timeAgo: String
    let isDead: Bool
    let isHnDeleted: Bool
    let kids: [Int]
    let fetchedAt: Date

    init(_ dto: HNItemDTO, storyID: Int, fetchedAt: Date = Date()) {
        id = dto.id
        self.storyID = storyID
        parentID = dto.parent
        author = dto.by
        text = dto.text
        plainText = dto.text?.strippedHTML ?? ""
        createdAt = dto.createdDate
        timeAgo = dto.createdDate?.timeAgoDisplay() ?? "unknown"
        isDead = dto.isDead
        isHnDeleted = dto.isDeleted
        kids = dto.kids ?? []
        self.fetchedAt = fetchedAt
    }

    init(_ cached: CachedComment) {
        id = cached.id
        storyID = cached.storyID
        parentID = cached.parentID
        author = cached.author
        text = cached.text
        plainText = cached.text?.strippedHTML ?? ""
        createdAt = cached.createdAt
        timeAgo = cached.createdAt?.timeAgoDisplay() ?? "unknown"
        isDead = cached.isDead
        isHnDeleted = cached.isHnDeleted
        kids = cached.kids
        fetchedAt = cached.lastFetchedAt
    }
}

/// A nested comment node. Collapse state is presentation-only.
struct CommentNode: Identifiable, Hashable {
    let id: Int
    let parentID: Int?
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

    init(comment: Comment, depth: Int, children: [CommentNode] = []) {
        id = comment.id
        parentID = comment.parentID
        author = comment.author
        text = comment.text
        plainText = comment.plainText
        createdAt = comment.createdAt
        timeAgo = comment.timeAgo
        isDead = comment.isDead
        isHnDeleted = comment.isHnDeleted
        self.depth = depth
        self.children = children
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
}

// MARK: - Saved

struct SavedStory: Identifiable, Hashable {
    var id: Int { storyID }
    let storyID: Int
    let savedAt: Date
    let title: String?
    let author: String?
    let url: String?
    let domain: String?
    let score: Int

    init(_ model: SavedStoryModel) {
        storyID = model.storyID
        savedAt = model.savedAt
        title = model.title
        author = model.author
        url = model.url
        let host = model.url.flatMap { URL(string: $0)?.host }
        domain = host?.replacingOccurrences(of: "www.", with: "")
        score = model.score
    }
}

// MARK: - Errors

enum BackendErrorCode: Int, Hashable, Sendable {
    case none = 0
    case offline = 1
    case timeout = 2
    case http = 3
    case decode = 4
    case notFound = 5
    case store = 6
    case cancelled = 7
    case unknown = 8
}

struct EngineError: Hashable {
    let code: BackendErrorCode
    let httpStatus: Int
    let message: String
    let retryable: Bool

    init(_ error: APIError) {
        switch error {
        case .networkUnavailable:
            code = .offline
            httpStatus = 0
            message = error.errorDescription ?? "You're offline."
            retryable = true
        case .requestTimeout:
            code = .timeout
            httpStatus = 0
            message = error.errorDescription ?? "The request timed out."
            retryable = true
        case .serverError(let status):
            code = .http
            httpStatus = status
            message = error.errorDescription ?? "Server error."
            retryable = true
        case .invalidResponse:
            code = .unknown
            httpStatus = 0
            message = error.errorDescription ?? "Invalid response."
            retryable = false
        case .decodingFailed:
            code = .decode
            httpStatus = 0
            message = error.errorDescription ?? "Couldn't decode the response."
            retryable = false
        case .itemNotFound:
            code = .notFound
            httpStatus = 0
            message = error.errorDescription ?? "Item not found."
            retryable = false
        case .persistenceError:
            code = .store
            httpStatus = 0
            message = error.errorDescription ?? "Storage error."
            retryable = false
        case .cancelled:
            code = .cancelled
            httpStatus = 0
            message = error.errorDescription ?? "Request cancelled."
            retryable = false
        case .unknown:
            code = .unknown
            httpStatus = 0
            message = error.errorDescription ?? "Something went wrong."
            retryable = false
        }
    }

    init(code: BackendErrorCode, httpStatus: Int = 0, message: String, retryable: Bool = false) {
        self.code = code
        self.httpStatus = httpStatus
        self.message = message
        self.retryable = retryable
    }
}

// MARK: - Snapshots

struct FeedSnapshotModel {
    let feed: FeedType
    let revision: UInt64
    let phase: LoadPhase
    let stories: [Story]
    let lastSyncAt: Date?
    let offline: Bool
    let stale: Bool
    let error: EngineError?

    static let idle = FeedSnapshotModel(feed: .top,
                                        revision: 0,
                                        phase: .idle,
                                        stories: [],
                                        lastSyncAt: nil,
                                        offline: false,
                                        stale: false,
                                        error: nil)
}

struct StorySnapshotModel {
    let storyID: Int
    let revision: UInt64
    let phase: LoadPhase
    let story: Story?
    let error: EngineError?
}

struct CommentsSnapshotModel {
    let storyID: Int
    let revision: UInt64
    let roots: [CommentNode]
    let totalLoaded: Int
    let loading: Bool
    let complete: Bool
    let error: EngineError?

    static func empty(storyID: Int) -> CommentsSnapshotModel {
        CommentsSnapshotModel(storyID: storyID,
                              revision: 0,
                              roots: [],
                              totalLoaded: 0,
                              loading: false,
                              complete: false,
                              error: nil)
    }
}

// MARK: - Telemetry

struct EngineMetrics: Hashable {
    var requests: UInt64 = 0
    var failures: UInt64 = 0
    var retries: UInt64 = 0
    var bytesReceived: UInt64 = 0
    var itemsParsed: UInt64 = 0
    var cacheHits: UInt64 = 0
    var cacheMisses: UInt64 = 0
    var snapshotsEmitted: UInt64 = 0
    var commentsFetched: UInt64 = 0
    var searchQueries: UInt64 = 0
    var inFlight: Int = 0
    var lastLatencyMs: Double = 0
    var averageLatencyMs: Double = 0

    static let empty = EngineMetrics()

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total == 0 ? 0 : Double(cacheHits) / Double(total)
    }

    mutating func apply(_ metrics: APIMetrics) {
        requests = metrics.requests
        failures = metrics.failures
        retries = metrics.retries
        bytesReceived = metrics.bytesReceived
        itemsParsed = metrics.itemsParsed
        inFlight = metrics.inFlight
        lastLatencyMs = metrics.lastLatencyMs
        averageLatencyMs = metrics.averageLatencyMs
    }
}

struct EngineStatus: Hashable {
    var revision: UInt64 = 0
    var feed: FeedType = .top
    var phase: LoadPhase = .idle
    var offline: Bool = false
    var lastSyncAt: Date?
    var cachedStories: Int = 0
    var cachedComments: Int = 0
    var savedCount: Int = 0
    var searchDocs: Int = 0
    var databaseBytes: Int64 = 0
    var uptimeSeconds: TimeInterval = 0
    var coreVersion: String = "Swift"
    var metrics: EngineMetrics = .empty

    static let empty = EngineStatus()

    var formattedDatabaseSize: String {
        ByteCountFormatter.string(fromByteCount: databaseBytes, countStyle: .file)
    }
}
