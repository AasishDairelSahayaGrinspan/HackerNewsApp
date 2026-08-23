import XCTest
@testable import HackerNews

final class HNItemDTOTests: XCTestCase {
    func testDecodingStory() throws {
        let json = """
        {
          "by" : "dhouston",
          "descendants" : 71,
          "id" : 8863,
          "kids" : [8952, 9224],
          "score" : 111,
          "time" : 1175714200,
          "title" : "My YC app: Dropbox - Throw away your USB drive",
          "type" : "story",
          "url" : "http://www.getdropbox.com/u/2/screencast.html"
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertEqual(item.id, 8863)
        XCTAssertEqual(item.by, "dhouston")
        XCTAssertEqual(item.title, "My YC app: Dropbox - Throw away your USB drive")
        XCTAssertEqual(item.score, 111)
        XCTAssertEqual(item.type, "story")
        XCTAssertEqual(item.kids?.count, 2)
        XCTAssertEqual(item.descendants, 71)
        XCTAssertNotNil(item.createdDate)
        XCTAssertEqual(item.domain, "getdropbox.com")
    }

    func testDecodingComment() throws {
        let json = """
        {
          "by" : "norvig",
          "id" : 2921983,
          "kids" : [2922097],
          "parent" : 2921506,
          "text" : "Aw shucks...",
          "time" : 1314211127,
          "type" : "comment"
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertEqual(item.id, 2921983)
        XCTAssertEqual(item.type, "comment")
        XCTAssertEqual(item.parent, 2921506)
        XCTAssertNotNil(item.text)
    }

    func testMissingFields() throws {
        let json = """
        {"id": 999, "type": "story"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertEqual(item.id, 999)
        XCTAssertNil(item.by)
        XCTAssertNil(item.title)
        XCTAssertNil(item.url)
        XCTAssertNil(item.score)
        XCTAssertFalse(item.isDeleted)
        XCTAssertFalse(item.isDead)
    }

    func testDeletedAndDead() throws {
        let json = """
        {"id": 123, "deleted": true, "dead": true, "type": "comment", "by": "user"}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertTrue(item.isDeleted)
        XCTAssertTrue(item.isDead)
    }

    func testForwardCompatibilityIgnoresUnknownFields() throws {
        let json = """
        {"id": 1, "type": "story", "unknownField": "surprise", "another": 123}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertEqual(item.id, 1)
    }

    func testMalformedResponseThrows() {
        let json = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(HNItemDTO.self, from: json))
    }

    func testJobDecoding() throws {
        let json = """
        {
          "by" : "justin",
          "id" : 192327,
          "score" : 6,
          "time" : 1210981217,
          "title" : "Justin.tv is looking for a Lead Flash Engineer!",
          "type" : "job",
          "url" : ""
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertEqual(item.type, "job")
        XCTAssertEqual(item.id, 192327)
    }

    func testPollDecoding() throws {
        let json = """
        {"id": 126809, "type": "poll", "title": "Poll test", "by": "pg", "parts": [126810], "score": 46, "time": 1204403652}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItemDTO.self, from: json)
        XCTAssertEqual(item.type, "poll")
        XCTAssertEqual(item.parts?.first, 126810)
    }

    func testEmptyUrlDomainNil() {
        let item = HNItemDTO(id: 1, deleted: nil, type: "story", by: "a", time: nil, text: nil, dead: nil, parent: nil, poll: nil, kids: nil, url: "", score: nil, title: nil, parts: nil, descendants: nil)
        XCTAssertNil(item.domain)
        // invalid url
        let item2 = HNItemDTO(id: 2, deleted: nil, type: "story", by: nil, time: nil, text: nil, dead: nil, parent: nil, poll: nil, kids: nil, url: "not a url", score: nil, title: nil, parts: nil, descendants: nil)
        XCTAssertNil(item2.domain)
    }
}
