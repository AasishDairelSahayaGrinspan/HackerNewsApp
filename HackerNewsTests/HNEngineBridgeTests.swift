import XCTest
@testable import HackerNews

final class HNEngineBridgeTests: XCTestCase {

    private final class Listener: NSObject, HNEngineListener {
        var feedExpectation: XCTestExpectation?
        var statusExpectation: XCTestExpectation?
        var savedExpectation: XCTestExpectation?
        var storyExpectation: XCTestExpectation?
        var commentsExpectation: XCTestExpectation?

        var lastFeed: HNFeedSnapshot?
        var lastStatus: HNStatus?
        var lastSaved: HNSavedSnapshot?

        func engine(_ engine: HNEngine, didUpdateFeed snapshot: HNFeedSnapshot) {
            lastFeed = snapshot
            let expectation = feedExpectation
            feedExpectation = nil
            expectation?.fulfill()
        }

        func engine(_ engine: HNEngine, didUpdateStory snapshot: HNStorySnapshot) {
            let expectation = storyExpectation
            storyExpectation = nil
            expectation?.fulfill()
        }

        func engine(_ engine: HNEngine, didUpdateComments snapshot: HNCommentsSnapshot) {
            let expectation = commentsExpectation
            commentsExpectation = nil
            expectation?.fulfill()
        }

        func engine(_ engine: HNEngine, didUpdateSaved snapshot: HNSavedSnapshot) {
            lastSaved = snapshot
            let expectation = savedExpectation
            savedExpectation = nil
            expectation?.fulfill()
        }

        func engine(_ engine: HNEngine, didUpdateStatus status: HNStatus) {
            lastStatus = status
            let expectation = statusExpectation
            statusExpectation = nil
            expectation?.fulfill()
        }
    }

    private func makeEngine() -> (HNEngine, Listener) {
        let engine = HNEngine(databasePath: ":memory:", baseURL: "invalid://localhost/")
        let listener = Listener()
        engine.listener = listener
        return (engine, listener)
    }

    private func waitForStart(_ engine: HNEngine, _ listener: Listener) {
        let status = expectation(description: "engine status")
        listener.statusExpectation = status
        engine.start()
        wait(for: [status], timeout: 5)
        listener.statusExpectation = nil
    }

    func testStatusAndVersionComeFromNativeEngine() {
        let (engine, listener) = makeEngine()
        defer { engine.shutdown() }

        waitForStart(engine, listener)

        let status = engine.status()
        XCTAssertFalse(engine.coreVersion().isEmpty)
        XCTAssertEqual(status.feed, .top)
        XCTAssertEqual(status.coreVersion, engine.coreVersion())
        XCTAssertGreaterThanOrEqual(status.metrics.snapshotsEmitted, 1)
    }

    func testSaveAndUnsaveRoundTrip() {
        let (engine, listener) = makeEngine()
        defer { engine.shutdown() }
        waitForStart(engine, listener)

        let saved = expectation(description: "saved snapshot")
        listener.savedExpectation = saved
        engine.setSaved(true, storyID: 42)
        wait(for: [saved], timeout: 5)
        listener.savedExpectation = nil

        XCTAssertTrue(engine.isSaved(42))
        XCTAssertEqual(engine.savedStories().count, 1)
        XCTAssertEqual(engine.savedStories().first?.storyID, 42)

        let unsaved = expectation(description: "unsaved snapshot")
        listener.savedExpectation = unsaved
        engine.setSaved(false, storyID: 42)
        wait(for: [unsaved], timeout: 5)
        listener.savedExpectation = nil

        XCTAssertFalse(engine.isSaved(42))
        XCTAssertTrue(engine.savedStories().isEmpty)
    }

    func testSearchIsLocalAndStartsEmpty() {
        let (engine, listener) = makeEngine()
        defer { engine.shutdown() }
        waitForStart(engine, listener)

        XCTAssertTrue(engine.search("swift", limit: 20).isEmpty)
        XCTAssertTrue(engine.search("", limit: 20).isEmpty)
    }

    func testClearEverythingRemovesSavedStories() {
        let (engine, listener) = makeEngine()
        defer { engine.shutdown() }
        waitForStart(engine, listener)

        let saved = expectation(description: "saved before clear")
        listener.savedExpectation = saved
        engine.setSaved(true, storyID: 7)
        wait(for: [saved], timeout: 5)
        listener.savedExpectation = nil
        XCTAssertEqual(engine.savedStories().count, 1)

        let cleared = expectation(description: "saved after clear")
        listener.savedExpectation = cleared
        engine.clearCache(keepSaved: false)
        wait(for: [cleared], timeout: 5)
        listener.savedExpectation = nil

        XCTAssertTrue(engine.savedStories().isEmpty)
    }

    func testOpenStoryProducesStorySnapshot() {
        let (engine, listener) = makeEngine()
        defer { engine.shutdown() }
        waitForStart(engine, listener)

        let story = expectation(description: "story snapshot")
        listener.storyExpectation = story
        engine.openStory(9001)
        wait(for: [story], timeout: 5)
        listener.storyExpectation = nil
    }
}
