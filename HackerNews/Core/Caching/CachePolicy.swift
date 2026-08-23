import Foundation

enum CachePolicy {
    /// Fresh if fetched within 5 minutes
    static let freshInterval: TimeInterval = 5 * 60
    /// Stale after 30 minutes, still show but refresh
    static let staleInterval: TimeInterval = 30 * 60
    /// Offline-only after 24h
    static let maxAge: TimeInterval = 24 * 60 * 60

    enum Freshness {
        case fresh
        case stale
        case expired
        case empty
    }

    static func freshness(lastFetched: Date?) -> Freshness {
        guard let date = lastFetched else { return .empty }
        let age = Date().timeIntervalSince(date)
        // Delegate to C++ core for single source of truth (C++20 CachePolicyCpp)
        let cppName = CppEngine.freshnessName(lastFetched: date) // via HNCppBridge/CachePolicyCpp
        switch cppName {
        case "fresh": return .fresh
        case "stale": return .stale
        case "expired": return .expired
        default: return .empty
        }
    }

    static var isFresh: Bool { freshness(lastFetched: Date()) == .fresh }
}
