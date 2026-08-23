import XCTest
import SwiftData
@testable import HackerNews

@MainActor
final class PersistenceTests: XCTestCase {
    var sut: PersistenceController!

    override func setUp() {
        super.setUp()
        sut = PersistenceController(inMemory: true)
    }

    func testSaveAndFetchStory() {
        let story = CachedStory(id: 123, title: "Test", author: "alice", score: 10)
        sut.context.insert(story)
        sut.save()
        let fetched = sut.fetchCachedStory(id: 123)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test")
    }

    func testSaveUnsave() {
        let story = CachedStory(id: 999, title: "Save me", author: "bob", score: 5)
        sut.context.insert(story)
        sut.save()
        XCTAssertFalse(sut.isSaved(storyID: 999))
        sut.saveStory(story)
        XCTAssertTrue(sut.isSaved(storyID: 999))
        XCTAssertEqual(sut.fetchSavedStories().count, 1)
        sut.unsaveStory(id: 999)
        XCTAssertFalse(sut.isSaved(storyID: 999))
        XCTAssertTrue(sut.fetchSavedStories().isEmpty)
    }

    func testSavedPersistsAcrossFetch() {
        let story = CachedStory(id: 555, title: "Persist", score: 1)
        sut.context.insert(story)
        sut.save()
        sut.saveStory(story)
        let saved = sut.fetchSavedStories().first
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.storyID, 555)
    }

    func testCacheMetadataUpdateAndFetch() {
        sut.updateCacheMetadata(feed: .top, ids: [1,2,3])
        let fetched = sut.fetchStories(for: .top)
        // No stories yet, so empty but metadata exists
        XCTAssertTrue(fetched.isEmpty)
        // Insert stories
        for id in [1,2,3] {
            sut.context.insert(CachedStory(id: id, title: "T\(id)", feedTypeRaw: FeedType.top.rawValue))
        }
        sut.save()
        let ordered = sut.fetchStories(for: .top)
        XCTAssertEqual(ordered.map(\.id), [1,2,3])
        XCTAssertNotNil(sut.lastFetched(for: .top))
    }

    func testCacheEvictionKeepsSaved() {
        let savedStory = CachedStory(id: 100, title: "Saved", lastFetchedAt: Date().addingTimeInterval(-60*60*24*10))
        let oldStory = CachedStory(id: 101, title: "Old", lastFetchedAt: Date().addingTimeInterval(-60*60*24*10))
        sut.context.insert(savedStory)
        sut.context.insert(oldStory)
        sut.save()
        sut.saveStory(savedStory)
        sut.updateCacheMetadata(feed: .top, ids: [100]) // only keep 100 in metadata
        sut.evictExpiredCache(maxFeedItems: 1, maxAge: 60*60*24*3)
        XCTAssertNotNil(sut.fetchCachedStory(id: 100), "Saved story must survive eviction")
        XCTAssertNil(sut.fetchCachedStory(id: 101), "Old unreferenced story should be evicted")
    }

    func testClearCacheKeepSaved() {
        let s1 = CachedStory(id: 1, title: "A")
        let s2 = CachedStory(id: 2, title: "B")
        sut.context.insert(s1)
        sut.context.insert(s2)
        sut.save()
        sut.saveStory(s1)
        sut.clearAllCache(keepSaved: true)
        XCTAssertNotNil(sut.fetchCachedStory(id: 1))
        XCTAssertNil(sut.fetchCachedStory(id: 2))
    }

    func testClearAllIncludingSaved() {
        let s = CachedStory(id: 9, title: "X")
        sut.context.insert(s)
        sut.save()
        sut.saveStory(s)
        sut.clearAllCache(keepSaved: false)
        XCTAssertTrue(sut.fetchSavedStories().isEmpty)
        XCTAssertNil(sut.fetchCachedStory(id: 9))
    }

    func testCommentPersistence() {
        let c = CachedComment(id: 500, storyID: 1, author: "tester", text: "hello")
        sut.context.insert(c)
        sut.save()
        let fetched = sut.fetchComments(for: 1)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.text, "hello")
    }

    func testFeedIsolation() {
        sut.updateCacheMetadata(feed: .top, ids: [1,2])
        sut.updateCacheMetadata(feed: .new, ids: [3,4])
        sut.context.insert(CachedStory(id: 1, title: "Top1", feedTypeRaw: FeedType.top.rawValue))
        sut.context.insert(CachedStory(id: 3, title: "New1", feedTypeRaw: FeedType.new.rawValue))
        sut.save()
        let top = sut.fetchStories(for: .top)
        let new = sut.fetchStories(for: .new)
        XCTAssertEqual(top.map(\.id), [1])
        XCTAssertEqual(new.map(\.id), [3])
    }
}
