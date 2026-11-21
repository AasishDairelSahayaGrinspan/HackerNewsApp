import XCTest
@testable import HackerNews

@MainActor
final class BackendLifecycleTests: XCTestCase {

    private func dto(id: Int, title: String, kids: [Int] = []) -> HNItemDTO {
        HNItemDTO(id: id,
                  deleted: nil,
                  type: "story",
                  by: "author\(id)",
                  time: 1_700_000_000,
                  text: nil,
                  dead: nil,
                  parent: nil,
                  poll: nil,
                  kids: kids,
                  url: "https://example.com/\(id)",
                  score: 10,
                  title: title,
                  parts: nil,
                  descendants: kids.count)
    }

    private func makeBackend(storyIDs: [Int],
                             items: [Int: HNItemDTO]) -> (AppBackend, MockHackerNewsAPI, PersistenceController) {
        let api = MockHackerNewsAPI()
        api.storyIDs[.top] = storyIDs
        api.items = items
        let persistence = PersistenceController(inMemory: true)
        let backend = AppBackend(api: api, persistence: persistence)
        return (backend, api, persistence)
    }

    /// The backend is intentionally asynchronous, so tests wait for the
    /// snapshot phase rather than assuming synchronous completion.
    private func waitForFeed(_ backend: AppBackend,
                             timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if backend.feed.phase == .loaded || backend.feed.phase == .failed {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for the feed to settle")
    }

    private func waitForStory(_ backend: AppBackend,
                              storyID: Int,
                              timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = backend.storySnapshot(for: storyID),
               snapshot.phase == .loaded || snapshot.phase == .failed {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for story \(storyID)")
    }

    func testStartLoadsCachedFeedAndServesStories() async {
        let persistence = PersistenceController(inMemory: true)
        let cached = Story(dto(id: 7, title: "Cached story"), feed: .top)
        persistence.upsertStories([cached])
        persistence.setFeedMeta(feed: .top, ids: [7], fetchedAt: Date())
        let api = MockHackerNewsAPI()
        api.storyIDs[.top] = [7]
        api.items = [7: dto(id: 7, title: "Cached story")]

        let backend = AppBackend(api: api, persistence: persistence)
        backend.start()
        await waitForFeed(backend)

        XCTAssertEqual(backend.feed.stories.map(\.id), [7])
        XCTAssertEqual(backend.feed.feed, .top)

        backend.shutdown()
    }

    func testToggleSaveUpdatesSnapshotsAndPersistence() async {
        let (backend, _, persistence) = makeBackend(
            storyIDs: [1],
            items: [1: dto(id: 1, title: "Save me")]
        )
        backend.start()
        await waitForFeed(backend)

        backend.setSaved(true, storyID: 1)
        XCTAssertTrue(backend.isSaved(1))
        XCTAssertTrue(persistence.isSaved(storyID: 1))
        XCTAssertEqual(backend.savedStories.map(\.storyID), [1])
        XCTAssertTrue(backend.feed.stories.first?.isSaved == true)

        backend.setSaved(false, storyID: 1)
        XCTAssertFalse(backend.isSaved(1))
        XCTAssertFalse(persistence.isSaved(storyID: 1))
        XCTAssertTrue(backend.savedStories.isEmpty)

        backend.shutdown()
    }

    func testSelectFeedUpdatesFeedSnapshot() async {
        let (backend, api, _) = makeBackend(storyIDs: [1, 2], items: [
            1: dto(id: 1, title: "Top story"),
            2: dto(id: 2, title: "Job story")
        ])
        api.storyIDs[.jobs] = [2]
        backend.start()
        await waitForFeed(backend)

        backend.selectFeed(.jobs)
        XCTAssertEqual(backend.feed.feed, .jobs)

        await waitForFeed(backend)
        XCTAssertEqual(backend.feed.stories.map(\.id), [2])

        backend.shutdown()
    }

    func testClearCacheKeepsSavedStories() async {
        let (backend, _, persistence) = makeBackend(
            storyIDs: [1, 2],
            items: [1: dto(id: 1, title: "One"), 2: dto(id: 2, title: "Two")]
        )
        backend.start()
        await waitForFeed(backend)
        backend.setSaved(true, storyID: 1)

        backend.clearCache(keepSaved: true)

        XCTAssertNotNil(persistence.fetchStory(id: 1))
        XCTAssertTrue(persistence.isSaved(storyID: 1))
        XCTAssertEqual(backend.savedStories.map(\.storyID), [1])

        backend.shutdown()
    }

    func testOpenStoryPopulatesStorySnapshot() async {
        let (backend, _, _) = makeBackend(
            storyIDs: [3],
            items: [3: dto(id: 3, title: "Detail")]
        )
        backend.start()
        await waitForFeed(backend)

        backend.openStory(3)
        await waitForStory(backend, storyID: 3)

        let snapshot = backend.storySnapshot(for: 3)
        XCTAssertEqual(snapshot?.story?.id, 3)
        XCTAssertEqual(snapshot?.phase, .loaded)

        backend.shutdown()
    }

    func testSearchFindsCachedStories() async {
        let (backend, _, _) = makeBackend(
            storyIDs: [5],
            items: [5: dto(id: 5, title: "Distributed systems deep dive")]
        )
        backend.start()
        await waitForFeed(backend)

        let results = backend.search("distributed")
        XCTAssertEqual(results.map(\.id), [5])

        backend.shutdown()
    }
}
