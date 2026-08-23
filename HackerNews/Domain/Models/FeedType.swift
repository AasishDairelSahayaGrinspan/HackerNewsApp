import Foundation

enum FeedType: String, CaseIterable, Identifiable, Sendable {
    case top = "Top"
    case new = "New"
    case best = "Best"
    case ask = "Ask"
    case show = "Show"
    case jobs = "Jobs"

    var id: String { rawValue }

    var endpointPath: String {
        switch self {
        case .top: return "topstories.json"
        case .new: return "newstories.json"
        case .best: return "beststories.json"
        case .ask: return "askstories.json"
        case .show: return "showstories.json"
        case .jobs: return "jobstories.json"
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
