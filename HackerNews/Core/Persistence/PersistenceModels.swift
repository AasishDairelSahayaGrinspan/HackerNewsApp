import Foundation
import SwiftData

// MARK: - CachedStory

@Model
final class CachedStory {
    @Attribute(.unique) var id: Int
    var type: String?
    var title: String?
    var author: String?
    var createdAt: Date?
    var score: Int
    var url: String?
    var text: String?
    var commentCount: Int
    var isDead: Bool
    var isHnDeleted: Bool
    var lastFetchedAt: Date
    var feedTypeRaw: String?

    var domain: String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    init(
        id: Int,
        type: String? = nil,
        title: String? = nil,
        author: String? = nil,
        createdAt: Date? = nil,
        score: Int = 0,
        url: String? = nil,
        text: String? = nil,
        commentCount: Int = 0,
        isDead: Bool = false,
        isHnDeleted: Bool = false,
        lastFetchedAt: Date = Date(),
        feedTypeRaw: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.author = author
        self.createdAt = createdAt
        self.score = score
        self.url = url
        self.text = text
        self.commentCount = commentCount
        self.isDead = isDead
        self.isHnDeleted = isHnDeleted
        self.lastFetchedAt = lastFetchedAt
        self.feedTypeRaw = feedTypeRaw
    }

    convenience init(from dto: HNItemDTO, feed: FeedType? = nil, fetchedAt: Date = Date()) {
        self.init(
            id: dto.id,
            type: dto.type,
            title: dto.title,
            author: dto.by,
            createdAt: dto.createdDate,
            score: dto.score ?? 0,
            url: dto.url,
            text: dto.text,
            commentCount: dto.descendants ?? dto.kids?.count ?? 0,
            isDead: dto.isDead,
            isHnDeleted: dto.isDeleted,
            lastFetchedAt: fetchedAt,
            feedTypeRaw: feed?.rawValue
        )
    }

    func update(from dto: HNItemDTO, feed: FeedType? = nil) {
        self.type = dto.type
        self.title = dto.title
        self.author = dto.by
        self.createdAt = dto.createdDate
        self.score = dto.score ?? score
        self.url = dto.url
        self.text = dto.text
        self.commentCount = dto.descendants ?? dto.kids?.count ?? commentCount
        self.isDead = dto.isDead
        self.isHnDeleted = dto.isDeleted
        self.lastFetchedAt = Date()
        if let feed { self.feedTypeRaw = feed.rawValue }
    }
}

// MARK: - CachedComment

@Model
final class CachedComment {
    @Attribute(.unique) var id: Int
    var storyID: Int
    var parentID: Int?
    var author: String?
    var text: String?
    var createdAt: Date?
    var isHnDeleted: Bool
    var isDead: Bool
    var kids: [Int]
    var lastFetchedAt: Date

    init(
        id: Int,
        storyID: Int,
        parentID: Int? = nil,
        author: String? = nil,
        text: String? = nil,
        createdAt: Date? = nil,
        isHnDeleted: Bool = false,
        isDead: Bool = false,
        kids: [Int] = [],
        lastFetchedAt: Date = Date()
    ) {
        self.id = id
        self.storyID = storyID
        self.parentID = parentID
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.isHnDeleted = isHnDeleted
        self.isDead = isDead
        self.kids = kids
        self.lastFetchedAt = lastFetchedAt
    }

    convenience init(from dto: HNItemDTO, storyID: Int) {
        self.init(
            id: dto.id,
            storyID: storyID,
            parentID: dto.parent,
            author: dto.by,
            text: dto.text,
            createdAt: dto.createdDate,
            isHnDeleted: dto.isDeleted,
            isDead: dto.isDead,
            kids: dto.kids ?? []
        )
    }
}

// MARK: - SavedStory

@Model
final class SavedStory {
    @Attribute(.unique) var storyID: Int
    var savedAt: Date
    var title: String?
    var author: String?
    var url: String?
    var score: Int

    init(storyID: Int, savedAt: Date = Date(), title: String? = nil, author: String? = nil, url: String? = nil, score: Int = 0) {
        self.storyID = storyID
        self.savedAt = savedAt
        self.title = title
        self.author = author
        self.url = url
        self.score = score
    }
}

// MARK: - CacheMetadata

@Model
final class CacheMetadata {
    @Attribute(.unique) var feedTypeRaw: String
    var lastFetchedAt: Date?
    var storyIDs: [Int]

    init(feedTypeRaw: String, lastFetchedAt: Date? = nil, storyIDs: [Int] = []) {
        self.feedTypeRaw = feedTypeRaw
        self.lastFetchedAt = lastFetchedAt
        self.storyIDs = storyIDs
    }

    var feedType: FeedType? { FeedType(rawValue: feedTypeRaw) }
}
