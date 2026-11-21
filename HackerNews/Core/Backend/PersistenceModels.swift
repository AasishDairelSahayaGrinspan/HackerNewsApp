import Foundation
import SwiftData

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
    var kids: [Int]

    var domain: String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    init(id: Int,
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
         feedTypeRaw: String? = nil,
         kids: [Int] = []) {
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
        self.kids = kids
    }

    convenience init(from story: Story) {
        self.init(id: story.id,
                  title: story.title,
                  author: story.author,
                  createdAt: story.createdAt,
                  score: story.score,
                  url: story.url,
                  text: story.text,
                  commentCount: story.commentCount,
                  isDead: story.isDead,
                  isHnDeleted: story.isHnDeleted,
                  lastFetchedAt: story.fetchedAt,
                  feedTypeRaw: story.feed.rawValue,
                  kids: story.kids)
    }

    func update(from story: Story) {
        title = story.title
        author = story.author
        createdAt = story.createdAt
        score = story.score
        url = story.url
        text = story.text
        commentCount = story.commentCount
        isDead = story.isDead
        isHnDeleted = story.isHnDeleted
        lastFetchedAt = story.fetchedAt
        feedTypeRaw = story.feed.rawValue
        kids = story.kids
    }
}

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

    init(id: Int,
         storyID: Int,
         parentID: Int? = nil,
         author: String? = nil,
         text: String? = nil,
         createdAt: Date? = nil,
         isHnDeleted: Bool = false,
         isDead: Bool = false,
         kids: [Int] = [],
         lastFetchedAt: Date = Date()) {
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

    convenience init(from comment: Comment) {
        self.init(id: comment.id,
                  storyID: comment.storyID,
                  parentID: comment.parentID,
                  author: comment.author,
                  text: comment.text,
                  createdAt: comment.createdAt,
                  isHnDeleted: comment.isHnDeleted,
                  isDead: comment.isDead,
                  kids: comment.kids,
                  lastFetchedAt: comment.fetchedAt)
    }

    func update(from comment: Comment) {
        storyID = comment.storyID
        parentID = comment.parentID
        author = comment.author
        text = comment.text
        createdAt = comment.createdAt
        isHnDeleted = comment.isHnDeleted
        isDead = comment.isDead
        kids = comment.kids
        lastFetchedAt = comment.fetchedAt
    }
}

@Model
final class SavedStoryModel {
    @Attribute(.unique) var storyID: Int
    var savedAt: Date
    var title: String?
    var author: String?
    var url: String?
    var score: Int

    init(storyID: Int,
         savedAt: Date = Date(),
         title: String? = nil,
         author: String? = nil,
         url: String? = nil,
         score: Int = 0) {
        self.storyID = storyID
        self.savedAt = savedAt
        self.title = title
        self.author = author
        self.url = url
        self.score = score
    }
}

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
