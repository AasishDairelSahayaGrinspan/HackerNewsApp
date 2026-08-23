import XCTest
@testable import HackerNews

@MainActor
final class StoryRepositoryTests: XCTestCase {
    var persistence: PersistenceController!
    var mockAPI: MockHackerNewsAPI!
    var sut: StoryRepository!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockAPI = MockHackerNewsAPI()
        sut = StoryRepository(api: mockAPI, persistence: persistence)
    }

    func testCacheFirstReturnsCachedWhenFresh() async {
        // Seed cache
        let story = CachedStory(id: 1, title: "Cached", author: "a", score: 10, lastFetchedAt: Date())
        persistence.context.insert(story)
        persistence.save()
        persistence.updateCacheMetadata(feed: .top, ids: [1])

        let state = await sut.stories(for: .top, page: 0, pageSize: 30)
        if case .loaded(let stories) = state {
            XCTAssertEqual(stories.first?.id, 1)
        } else {
            XCTFail("Expected loaded cached")
        }
    }

    func testRefreshMergesNetworkData() async throws {
        mockAPI.storyIDs[.top] = [10,11]
        mockAPI.items[10] = HNItemDTO(id: 10, deleted: nil, type: "story", by: "alice", time: Date().timeIntervalSince1970, text: nil, dead: nil, parent: nil, poll: nil, kids: nil, url: "https://example.com", score: 42, title: "Network Story", parts: nil, descendants: 5)
        mockAPI.items[11] = HNItemDTO(id: 11, deleted: nil, type: "story", by: "bob", time: Date().timeIntervalSince1970, text: nil, dead: nil, parent: nil, poll: nil, kids: nil, url: nil, score: 10, title: "Second", parts: nil, descendants: 0)

        let state = await sut.refresh(feed: .top)
        if case .loaded(let stories) = state {
            XCTAssertEqual(stories.count, 2)
        } else {
            XCTFail("Expected loaded after refresh")
        }
        // Check persisted
        XCTAssertNotNil(persistence.fetchCachedStory(id: 10))
        XCTAssertEqual(persistence.fetchCachedStory(id: 10)?.title, "Network Story")
    }

    func testOfflineReturnsCachedWithError() async {
        // Seed cached
        let story = CachedStory(id: 99, title: "Offline", lastFetchedAt: Date().addingTimeInterval(-1000))
        persistence.context.insert(story)
        persistence.save()
        persistence.updateCacheMetadata(feed: .top, ids: [99])

        mockAPI.shouldFail = true
        mockAPI.errorToThrow = .networkUnavailable

        let state = await sut.refresh(feed: .top)
        if case .failed(let cached, let err) = state {
            XCTAssertEqual(err, .networkUnavailable)
            XCTAssertEqual(cached?.first?.id, 99)
        } else {
            XCTFail("Expected failed with cached")
        }
    }

    func testFetchStoryUsesCacheWhenFresh() async throws {
        let story = CachedStory(id: 500, title: "Fresh", lastFetchedAt: Date())
        persistence.context.insert(story)
        persistence.save()

        // No API setup, should return cached without hitting network
        let fetched = try await sut.fetchStory(id: 500)
        XCTAssertEqual(fetched.title, "Fresh")
    }

    func testToggleSaveLocalOnly() {
        let story = CachedStory(id: 777, title: "SaveTest")
        persistence.context.insert(story)
        persistence.save()
        XCTAssertFalse(sut.isSaved(storyID: 777))
        let saved = sut.toggleSave(storyID: 777)
        XCTAssertTrue(saved)
        XCTAssertTrue(sut.isSaved(storyID: 777))
        let unsaved = sut.toggleSave(storyID: 777)
        XCTAssertFalse(unsaved)
    }

    func testSearchFindsCachedContent() {
        let s1 = CachedStory(id: 1, title: "Swift Concurrency Deep Dive", author: "alice", url: "https://swift.org")
        let s2 = CachedStory(id: 2, title: "Python Tips", author: "bob")
        persistence.context.insert(s1)
        persistence.context.insert(s2)
        persistence.save()

        let results = sut.search(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, 1)

        let authorResults = sut.search(query: "bob")
        XCTAssertEqual(authorResults.count, 1)
    }

    func testSavedNotDeletedByRefresh() async {
        let story = CachedStory(id: 1000, title: "Keep me")
        persistence.context.insert(story)
        persistence.save()
        _ = sut.toggleSave(storyID: 1000)
        XCTAssertTrue(sut.isSaved(storyID: 1000))

        // Refresh with different IDs (story 1000 not in feed anymore)
        mockAPI.storyIDs[.top] = [2000]
        mockAPI.items[2000] = HNItemDTO(id: 2000, deleted: nil, type: "story", by: "x", time: Date().timeIntervalSince1970, text: nil, dead: nil, parent: nil, poll: nil, kids: nil, url: nil, score: 1, title: "New", parts: nil, descendants: nil)
        _ = await sut.refresh(feed: .top)

        XCTAssertTrue(sut.isSaved(storyID: 1000), "Saved story must survive feed refresh not containing it")
        XCTAssertNotNil(persistence.fetchCachedStory(id: 1000))
    }
}
