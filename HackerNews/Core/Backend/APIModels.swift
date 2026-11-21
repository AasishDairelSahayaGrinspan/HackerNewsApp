import Foundation

// MARK: - Wire item

/// Any Hacker News item (story, comment, job, poll, pollopt).
struct HNItemDTO: Codable, Sendable, Equatable {
    let id: Int
    let deleted: Bool?
    let type: String?
    let by: String?
    let time: TimeInterval?
    let text: String?
    let dead: Bool?
    let parent: Int?
    let poll: Int?
    let kids: [Int]?
    let url: String?
    let score: Int?
    let title: String?
    let parts: [Int]?
    let descendants: Int?

    var isDeleted: Bool { deleted == true }
    var isDead: Bool { dead == true }

    var itemType: HNItemType {
        guard let type else { return .unknown }
        return HNItemType(rawValue: type) ?? .unknown
    }

    var domain: String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var createdDate: Date? {
        guard let time else { return nil }
        return Date(timeIntervalSince1970: time)
    }
}

enum HNItemType: String, Codable, Sendable {
    case job
    case story
    case comment
    case poll
    case pollopt
    case unknown
}

// MARK: - Metrics

struct APIMetrics: Sendable, Hashable {
    var requests: UInt64 = 0
    var failures: UInt64 = 0
    var retries: UInt64 = 0
    var bytesReceived: UInt64 = 0
    var itemsParsed: UInt64 = 0
    var inFlight: Int = 0
    var lastLatencyMs: Double = 0
    var totalLatencyMs: Double = 0
    var latencySamples: UInt64 = 0

    var averageLatencyMs: Double {
        latencySamples == 0 ? 0 : totalLatencyMs / Double(latencySamples)
    }
}
