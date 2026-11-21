import XCTest
import SwiftData
@testable import HackerNews

@MainActor
final class BackendPersistenceTests: XCTestCase {

    private func makeStory(id: Int = 1,
                           title: String = "A cached story",
                           feed: FeedType = .top) -> Story {
        let dto = HNItemDTO(id: id,
                            deleted: nil,
                            type: "story",
                            by: "alice",
                            time: 1_700_000_000,
                            text: "<p>Body</p>",
                            dead: nil,
                            parent: nil,
                            poll: nil,
                            kids: [11, 12],
                            url: "https://www.example.com/post",
                            score: 42,
                            title: title,
                            parts: nil,
                            descendants: 2)
        return Story(dto, feed: feed)
    }

    func testStoriesAndFeedMetadataRoundTrip() {
        let persistence = PersistenceController(inMemory: true)
        let story = makeStory()

        persistence.upsertStories([story])
        persistence.setFeedMeta(feed: .top, ids: [1], fetchedAt: Date())

        let cached = persistence.fetchStories(ids: [1])
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached.first?.title, "A cached story")
        XCTAssertEqual(cached.first?.domain, "example.com")
        XCTAssertEqual(cached.first?.kids, [11, 12])

        let meta = persistence.fetchFeedMeta(feed: .top)
        XCTAssertEqual(meta?.ids, [1])
        XCTAssertNotNil(meta?.fetchedAt)
        XCTAssertEqual(persistence.countStories(), 1)
    }

    func testStoryUpsertUpdatesExistingRow() {
        let persistence = PersistenceController(inMemory: true)
        persistence.upsertStories([makeStory(title: "First")])

        var updated = makeStory(title: "Second")
        updated = Story(id: updated.id,
                        title: updated.title,
                        author: updated.author,
                        url: updated.url,
                        text: updated.text,
                        plainText: updated.plainText,
                        domain: updated.domain,
                        timeAgo: updated.timeAgo,
                        score: 99,
                        commentCount: updated.commentCount,
                        createdAt: updated.createdAt,
                        isDead: updated.isDead,
                        isHnDeleted: updated.isHnDeleted,
                        isSaved: updated.isSaved,
                        feed: updated.feed,
                        kids: updated.kids,
                        fetchedAt: updated.fetchedAt)
        persistence.upsertStories([updated])

        XCTAssertEqual(persistence.countStories(), 1)
        XCTAssertEqual(persistence.fetchStory(id: 1)?.title, "Second")
        XCTAssertEqual(persistence.fetchStory(id: 1)?.score, 99)
    }

    func testCommentsRoundTripAndUpdate() {
        let persistence = PersistenceController(inMemory: true)
        let first = Comment(HNItemDTO(id: 11,
                                      deleted: nil,
                                      type: "comment",
                                      by: "bob",
                                      time: 1_700_000_100,
                                      text: "<p>First</p>",
                                      dead: nil,
                                      parent: 1,
                                      poll: nil,
                                      kids: [12],
                                      url: nil,
                                      score: nil,
                                      title: nil,
                                      parts: nil,
                                      descendants: nil),
                            storyID: 1)
        let second = Comment(HNItemDTO(id: 12,
                                       deleted: nil,
                                       type: "comment",
                                       by: "carol",
                                       time: 1_700_000_200,
                                       text: "Second",
                                       dead: nil,
                                       parent: 11,
                                       poll: nil,
                                       kids: [],
                                       url: nil,
                                       score: nil,
                                       title: nil,
                                       parts: nil,
                                       descendants: nil),
                             storyID: 1)

        persistence.upsertComments([first, second])
        XCTAssertEqual(persistence.fetchComments(storyID: 1).count, 2)
        XCTAssertEqual(persistence.countComments(), 2)

        let edited = Comment(HNItemDTO(id: 11,
                                       deleted: nil,
                                       type: "comment",
                                       by: "bob",
                                       time: 1_700_000_100,
                                       text: "Edited",
                                       dead: nil,
                                       parent: 1,
                                       poll: nil,
                                       kids: [],
                                       url: nil,
                                       score: nil,
                                       title: nil,
                                       parts: nil,
                                       descendants: nil),
                             storyID: 1)
        persistence.upsertComments([edited])

        XCTAssertEqual(persistence.countComments(), 2)
        let updated = persistence.fetchComments(storyID: 1).first { $0.id == 11 }
        XCTAssertEqual(updated?.text, "Edited")
        XCTAssertEqual(updated?.kids, [])
    }

    func testSavedStoryIsKeptWhenClearingCache() {
        let persistence = PersistenceController(inMemory: true)
        let story = makeStory()
        persistence.upsertStories([story])
        persistence.setSaved(true, storyID: story.id, story: story)

        XCTAssertTrue(persistence.isSaved(storyID: story.id))
        XCTAssertEqual(persistence.countSaved(), 1)

        persistence.clear(keepSaved: true)
        XCTAssertNotNil(persistence.fetchStory(id: story.id))
        XCTAssertTrue(persistence.isSaved(storyID: story.id))

        persistence.clear(keepSaved: false)
        XCTAssertNil(persistence.fetchStory(id: story.id))
        XCTAssertEqual(persistence.countSaved(), 0)
        XCTAssertEqual(persistence.countStories(), 0)
    }

    func testEvictionKeepsSavedStories() {
        let persistence = PersistenceController(inMemory: true)
        let savedStory = makeStory(id: 1, title: "Saved")
        let oldStory = makeStory(id: 2, title: "Old")
        persistence.upsertStories([savedStory, oldStory])
        persistence.setSaved(true, storyID: savedStory.id, story: savedStory)
        persistence.setFeedMeta(feed: .top, ids: [savedStory.id], fetchedAt: Date())

        persistence.evict(maxFeedItems: 1, maxAge: 0)

        XCTAssertNotNil(persistence.fetchStory(id: savedStory.id))
        XCTAssertNil(persistence.fetchStory(id: oldStory.id))
    }
}
