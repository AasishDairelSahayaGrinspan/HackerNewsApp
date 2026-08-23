import Foundation

// MARK: - HNItemDTO
// Represents any Hacker News item (story, comment, job, poll, pollopt)
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

    // Forward-compatibility: unknown fields are ignored by Codable automatically

    var isDeleted: Bool { deleted == true }
    var isDead: Bool { dead == true }

    var itemType: HNItemType {
        guard let type else { return .unknown }
        return HNItemType(rawValue: type) ?? .unknown
    }

    var domain: String? {
        guard let url else { return nil }
        // C++ domain extraction (HNCppEngine::extractDomain) - consistent with C++ core
        return CppEngine.domain(from: url)
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

// MARK: - Equatable for testability handled via synthesized
