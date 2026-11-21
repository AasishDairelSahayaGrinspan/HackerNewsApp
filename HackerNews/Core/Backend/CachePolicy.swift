import Foundation

enum CacheFreshness: Equatable, Sendable {
    case fresh
    case stale
    case expired
    case empty
}

/// Single source of truth for retention. The backend, not the views, decides
/// when cached content is usable.
enum CachePolicy {
    static let freshInterval: TimeInterval = 5 * 60
    static let staleInterval: TimeInterval = 30 * 60
    static let maxAge: TimeInterval = 24 * 60 * 60
    static let evictionAge: TimeInterval = 3 * 24 * 60 * 60
    static let evictionFeedItems = 200

    static func freshness(lastFetched: Date?, now: Date = Date()) -> CacheFreshness {
        guard let lastFetched else { return .empty }
        return freshness(age: now.timeIntervalSince(lastFetched))
    }

    static func freshness(age: TimeInterval) -> CacheFreshness {
        if age < 0 { return .empty }
        if age < freshInterval { return .fresh }
        if age < staleInterval { return .stale }
        if age < maxAge { return .expired }
        return .empty
    }

    static func isFresh(_ date: Date?) -> Bool {
        freshness(lastFetched: date) == .fresh
    }
}
