import Foundation

/// Feed identifiers mirror the native engine's `hn::Feed`. Swift never
/// constructs API paths; it only forwards the selected feed across the bridge.
enum FeedType: String, CaseIterable, Identifiable, Sendable {
    case top = "Top"
    case new = "New"
    case best = "Best"
    case ask = "Ask"
    case show = "Show"
    case jobs = "Jobs"

    var id: String { rawValue }

    var bridgeValue: HNFeed {
        switch self {
        case .top: return .top
        case .new: return .new
        case .best: return .best
        case .ask: return .ask
        case .show: return .show
        case .jobs: return .jobs
        }
    }

    init(_ feed: HNFeed) {
        switch feed {
        case .new: self = .new
        case .best: self = .best
        case .ask: self = .ask
        case .show: self = .show
        case .jobs: self = .jobs
        default: self = .top
        }
    }

    var icon: String {
        switch self {
        case .top: return "flame.fill"
        case .new: return "clock.fill"
        case .best: return "star.fill"
        case .ask: return "questionmark.bubble.fill"
        case .show: return "eye.fill"
        case .jobs: return "briefcase.fill"
        }
    }

    var description: String {
        switch self {
        case .top: return "Most popular stories right now"
        case .new: return "Fresh submissions"
        case .best: return "Highest voted stories"
        case .ask: return "Ask Hacker News"
        case .show: return "Show your work"
        case .jobs: return "Who is hiring"
        }
    }
}
