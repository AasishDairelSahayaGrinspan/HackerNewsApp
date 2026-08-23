import XCTest
@testable import HackerNews

@MainActor
final class CommentTests: XCTestCase {
    var persistence: PersistenceController!
    var mockAPI: MockHackerNewsAPI!
    var repo: CommentRepository!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        mockAPI = MockHackerNewsAPI()
        repo = CommentRepository(api: mockAPI, persistence: persistence)
    }

    func testBuildTreeHierarchy() {
        let c1 = CachedComment(id: 1, storyID: 100, kids: [2,3])
        let c2 = CachedComment(id: 2, storyID: 100, parentID: 1)
        let c3 = CachedComment(id: 3, storyID: 100, parentID: 1, kids: [4])
        let c4 = CachedComment(id: 4, storyID: 100, parentID: 3)
        let nodes = repo.buildTree(comments: [c1,c2,c3,c4], rootKids: [1])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].id, 1)
        XCTAssertEqual(nodes[0].children.count, 2)
        XCTAssertEqual(nodes[0].children[1].children.first?.id, 4)
    }

    func testBuildTreeFlatWhenNoRootKids() {
        let c1 = CachedComment(id: 10, storyID: 1, kids: [])
        let c2 = CachedComment(id: 11, storyID: 1, kids: [])
        let nodes = repo.buildTree(comments: [c1,c2], rootKids: nil)
        // Without rootKids, both are roots (neither is child of other)
        XCTAssertEqual(nodes.count, 2)
    }

    func testLoadCommentsOfflineUsesCache() async {
        let story = CachedStory(id: 999, title: "Story", lastFetchedAt: Date())
        persistence.context.insert(story)
        let cached = CachedComment(id: 500, storyID: 999, text: "cached")
        persistence.context.insert(cached)
        persistence.save()

        let nodes = await repo.loadComments(for: story)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.comment.text, "cached")
    }

    func testLoadCommentsFetchesNetwork() async {
        let story = CachedStory(id: 1000, title: "NetStory", lastFetchedAt: Date.distantPast)
        persistence.context.insert(story)
        persistence.save()
        // Mock story item with kids
        mockAPI.items[1000] = HNItemDTO(id: 1000, deleted: nil, type: "story", by: "a", time: Date().timeIntervalSince1970, text: nil, dead: nil, parent: nil, poll: nil, kids: [2000], url: nil, score: nil, title: "Net", parts: nil, descendants: 1)
        mockAPI.items[2000] = HNItemDTO(id: 2000, deleted: nil, type: "comment", by: "bob", time: Date().timeIntervalSince1970, text: "hello world", dead: nil, parent: 1000, poll: nil, kids: nil, url: nil, score: nil, title: nil, parts: nil, descendants: nil)

        let nodes = await repo.loadComments(for: story)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.comment.id, 2000)
        XCTAssertTrue(persistence.fetchComments(for: 1000).count >= 1)
    }

    func testDeletedCommentHandling() async {
        let story = CachedStory(id: 1, title: "t")
        persistence.context.insert(story)
        persistence.save()
        let dto1 = HNItemDTO(id: 1, deleted: nil, type: "story", by: "a", time: Date().timeIntervalSince1970, text: nil, dead: nil, parent: nil, poll: nil, kids: [2], url: nil, score: nil, title: nil, parts: nil, descendants: nil)
        let dto2 = HNItemDTO(id: 2, deleted: true, type: "comment", by: nil, time: nil, text: nil, dead: nil, parent: 1, poll: nil, kids: nil, url: nil, score: nil, title: nil, parts: nil, descendants: nil)
        mockAPI.items[1] = dto1
        mockAPI.items[2] = dto2

        let nodes = await repo.loadComments(for: story)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes.first?.comment.isHnDeleted == true)
    }

    func testCollapseStatePreserved() {
        let c = CachedComment(id: 1, storyID: 1, kids: [2])
        let child = CachedComment(id: 2, storyID: 1)
        var nodes = repo.buildTree(comments: [c, child], rootKids: [1])
        XCTAssertFalse(nodes[0].isCollapsed)
        nodes[0].isCollapsed = true
        XCTAssertTrue(nodes[0].isCollapsed)
    }
}
