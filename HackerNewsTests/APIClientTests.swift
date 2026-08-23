import XCTest
@testable import HackerNews

final class APIClientTests: XCTestCase {
    func testAPIErrorMapping() {
        let urlErr = URLError(.notConnectedToInternet)
        XCTAssertEqual(APIError.map(urlErr), .networkUnavailable)

        let timeout = URLError(.timedOut)
        XCTAssertEqual(APIError.map(timeout), .requestTimeout)

        let cancelled = URLError(.cancelled)
        XCTAssertEqual(APIError.map(cancelled), .cancelled)
    }

    func testAPIErrorDescriptionsAreUserFriendly() {
        XCTAssertTrue(APIError.networkUnavailable.errorDescription?.contains("offline") == true)
        XCTAssertFalse(APIError.networkUnavailable.errorDescription?.contains("NSURLErrorDomain") == true)
        XCTAssertTrue(APIError.requestTimeout.errorDescription?.contains("timed out") == true)
    }

    func testEndpointURLConstruction() {
        let base = URL(string: "https://hacker-news.firebaseio.com/v0/")!
        let ep = Endpoint(path: "topstories.json")
        XCTAssertEqual(ep.url(baseURL: base)?.absoluteString, "https://hacker-news.firebaseio.com/v0/topstories.json")

        let ep2 = Endpoint(path: "item/123.json")
        XCTAssertTrue(ep2.url(baseURL: base)?.absoluteString.contains("item/123.json") == true)
    }

    func testMockAPIClientReturnsStub() async throws {
        let mock = MockAPIClient()
        try await mock.stub([1,2,3], for: "topstories.json")
        let result: [Int] = try await mock.fetch([Int].self, endpoint: Endpoint(path: "topstories.json"))
        XCTAssertEqual(result, [1,2,3])
    }

    func testFeedTypeEndpoints() {
        XCTAssertEqual(FeedType.top.endpointPath, "topstories.json")
        XCTAssertEqual(FeedType.ask.endpointPath, "askstories.json")
        XCTAssertEqual(FeedType.jobs.endpointPath, "jobstories.json")
        XCTAssertEqual(FeedType.show.endpointPath, "showstories.json")
    }

    func testCachePolicyFreshness() {
        XCTAssertEqual(CachePolicy.freshness(lastFetched: nil), .empty)
        XCTAssertEqual(CachePolicy.freshness(lastFetched: Date()), .fresh)
        XCTAssertEqual(CachePolicy.freshness(lastFetched: Date().addingTimeInterval(-60*10)), .stale)
        XCTAssertEqual(CachePolicy.freshness(lastFetched: Date().addingTimeInterval(-60*60)), .expired)
    }
}
