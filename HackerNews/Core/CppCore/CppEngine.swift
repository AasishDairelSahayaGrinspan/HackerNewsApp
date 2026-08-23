import Foundation

/// Swift facade for HackerNews C++ Core Engine
/// All heavy algorithms (deduplication, chunking, HTML, freshness, domain) run in C++20 for performance
enum CppEngine {

    // MARK: - Feed

    static func endpoint(for feed: FeedType) -> String {
        // Direct Swift is fine, but demonstrate C++ path
        HNCppBridge.endpoint(forFeed: feed.rawValue)
    }

    static func isFresh(lastFetched: Date?) -> Bool {
        guard let date = lastFetched else { return false }
        let age = Date().timeIntervalSince(date)
        return HNCppBridge.isFresh(withAge: age)
    }

    static func freshnessName(lastFetched: Date?) -> String {
        guard let date = lastFetched else { return "empty" }
        let age = Date().timeIntervalSince(date)
        return HNCppBridge.freshness(forAge: age) as String
    }

    // MARK: - IDs

    static func deduplicate(_ ids: [Int]) -> [Int] {
        let arr = ids.map { NSNumber(value: $0) }
        let out = HNCppBridge.deduplicateIDs(arr)
        return out.map { $0.intValue }
    }

    static func chunk(_ ids: [Int], size: Int) -> [[Int]] {
        let arr = ids.map { NSNumber(value: $0) }
        let chunks = HNCppBridge.chunkIDs(arr, chunkSize: size)
        return chunks.map { $0.map { $0.intValue } }
    }

    // MARK: - Text

    static func stripHTML(_ html: String) -> String {
        HNCppBridge.stripHTML(html) as String
    }

    static func domain(from urlString: String) -> String? {
        let d = HNCppBridge.domain(fromURL: urlString) as String
        return d.isEmpty ? nil : d
    }

    static func timeAgo(from unixTime: TimeInterval) -> String {
        HNCppBridge.timeAgo(fromUnixTime: unixTime) as String
    }

    static func storyURL(id: Int) -> URL? {
        let s = HNCppBridge.storyURL(forID: id) as String
        return URL(string: s)
    }

    static func version() -> String {
        HNCppBridge.cppCoreVersion() as String
    }

    static func stats(commentCount: Int, depth: Int) -> [String: Any] {
        (HNCppBridge.engineStats(forCommentCount: commentCount, depth: depth) as NSDictionary) as! [String: Any]
    }
}
