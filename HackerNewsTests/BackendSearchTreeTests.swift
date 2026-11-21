import XCTest
@testable import HackerNews

@MainActor
final class BackendSearchTreeTests: XCTestCase {

    // MARK: - Comment tree

    private func comment(id: Int,
                         parent: Int?,
                         kids: [Int] = [],
                         text: String = "body") -> Comment {
        let dto = HNItemDTO(id: id,
                            deleted: nil,
                            type: "comment",
                            by: "user\(id)",
                            time: 1_700_000_000,
                            text: text,
                            dead: nil,
                            parent: parent,
                            poll: nil,
                            kids: kids,
                            url: nil,
                            score: nil,
                            title: nil,
                            parts: nil,
                            descendants: nil)
        return Comment(dto, storyID: 1)
    }

    func testTreeNestsChildrenAndPreservesOrder() {
        let comments = [
            comment(id: 10, parent: 1, kids: [11, 12]),
            comment(id: 11, parent: 10, kids: [13]),
            comment(id: 12, parent: 10),
            comment(id: 13, parent: 11)
        ]

        let roots = CommentTree.build(comments: comments, rootKids: [10])

        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.id, 10)
        XCTAssertEqual(roots.first?.children.map(\.id), [11, 12])
        XCTAssertEqual(roots.first?.children.first?.children.map(\.id), [13])
        XCTAssertEqual(CommentTree.count(roots), 4)
    }

    func testTreeFallsBackToParentlessRoots() {
        let comments = [
            comment(id: 20, parent: nil, kids: [21]),
            comment(id: 21, parent: 20)
        ]

        let roots = CommentTree.build(comments: comments, rootKids: [])

        XCTAssertEqual(roots.map(\.id), [20])
        XCTAssertEqual(roots.first?.children.first?.id, 21)
    }

    func testTreeIgnoresCycles() {
        let comments = [
            comment(id: 30, parent: nil, kids: [31]),
            comment(id: 31, parent: 30, kids: [30])
        ]

        let roots = CommentTree.build(comments: comments, rootKids: [30])

        XCTAssertEqual(CommentTree.count(roots), 2)
        XCTAssertEqual(roots.first?.children.first?.children.count, 0)
    }

    func testTreeHonoursMaxDepth() {
        let comments = [
            comment(id: 40, parent: nil, kids: [41]),
            comment(id: 41, parent: 40, kids: [42]),
            comment(id: 42, parent: 41)
        ]

        let roots = CommentTree.build(comments: comments, rootKids: [40], maxDepth: 1)

        XCTAssertEqual(roots.first?.children.count, 1)
        XCTAssertEqual(roots.first?.children.first?.children.count, 0)
        XCTAssertEqual(CommentTree.count(roots), 2)
    }

    // MARK: - Search

    private func story(id: Int,
                       title: String,
                       author: String = "alice",
                       url: String? = nil,
                       score: Int = 0,
                       time: TimeInterval = 1_700_000_000) -> Story {
        Story(id: id,
              title: title,
              author: author,
              url: url,
              text: nil,
              plainText: "",
              domain: url.flatMap { URL(string: $0)?.host },
              timeAgo: "",
              score: score,
              commentCount: 0,
              createdAt: Date(timeIntervalSince1970: time))
    }

    func testSearchRanksTitleMatchesAndIsCaseInsensitive() {
        let index = SearchIndex()
        index.upsert(story(id: 1, title: "Swift concurrency explained", score: 10))
        index.upsert(story(id: 2, title: "Rust ownership", score: 99))
        index.upsert(story(id: 3, title: "Weekly roundup", author: "swiftfan"))

        let results = index.search("swift")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains(1))
        XCTAssertTrue(results.contains(3))
    }

    func testSearchMatchesDomainPrefix() {
        let index = SearchIndex()
        index.upsert(story(id: 1, title: "A post", url: "https://github.com/foo/bar"))
        index.upsert(story(id: 2, title: "Another", url: "https://example.com/x"))

        XCTAssertEqual(index.search("git"), [1])
        XCTAssertEqual(index.search("example"), [2])
    }

    func testSearchUpsertAndRemoveMaintainIndex() {
        let index = SearchIndex()
        let first = story(id: 1, title: "Old title about databases")
        index.upsert(first)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.search("databases"), [1])

        index.upsert(story(id: 1, title: "New title about compilers"))
        XCTAssertEqual(index.search("databases"), [])
        XCTAssertEqual(index.search("compilers"), [1])
        XCTAssertEqual(index.count, 1)

        index.remove(1)
        XCTAssertEqual(index.count, 0)
        XCTAssertEqual(index.search("compilers"), [])
    }

    func testEmptyQueryReturnsNothing() {
        let index = SearchIndex()
        index.upsert(story(id: 1, title: "Anything"))
        XCTAssertEqual(index.search("   "), [])
    }

    // MARK: - Cache policy

    func testCacheFreshnessThresholds() {
        XCTAssertEqual(CachePolicy.freshness(lastFetched: nil), .empty)
        XCTAssertEqual(CachePolicy.freshness(age: 60), .fresh)
        XCTAssertEqual(CachePolicy.freshness(age: 10 * 60), .stale)
        XCTAssertEqual(CachePolicy.freshness(age: 2 * 60 * 60), .expired)
        XCTAssertEqual(CachePolicy.freshness(age: 48 * 60 * 60), .empty)
        XCTAssertTrue(CachePolicy.isFresh(Date()))
        XCTAssertFalse(CachePolicy.isFresh(Date().addingTimeInterval(-3600)))
    }
}
