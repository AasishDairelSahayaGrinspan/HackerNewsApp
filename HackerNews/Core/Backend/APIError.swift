import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case networkUnavailable
    case requestTimeout
    case serverError(statusCode: Int)
    case invalidResponse
    case decodingFailed(String)
    case itemNotFound(Int)
    case persistenceError(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "You're offline. Showing the latest cached content."
        case .requestTimeout:
            return "The request timed out. Please try again."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .invalidResponse:
            return "Received an unexpected response. Please try again."
        case .decodingFailed(let message):
            return "Couldn't process the data: \(message)"
        case .itemNotFound(let id):
            return "Story \(id) couldn't be found."
        case .persistenceError(let message):
            return "Storage error: \(message)"
        case .cancelled:
            return "Request was cancelled."
        case .unknown(let message):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .requestTimeout:
            return true
        case .serverError(let code):
            return code == 429 || (500..<600).contains(code)
        case .invalidResponse, .decodingFailed, .itemNotFound, .persistenceError, .cancelled, .unknown:
            return false
        }
    }

    static func map(_ error: Error) -> APIError {
        if let api = error as? APIError { return api }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .requestTimeout
            case .cancelled:
                return .cancelled
            default:
                return .unknown(urlError.localizedDescription)
            }
        }
        if error is DecodingError {
            return .decodingFailed(error.localizedDescription)
        }
        return .unknown(error.localizedDescription)
    }
}
