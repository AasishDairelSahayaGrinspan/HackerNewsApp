import Foundation

enum LoadState<Value>: Equatable where Value: Equatable {
    case idle
    case loading
    case loaded(Value)
    case refreshing(Value)
    case failed(Value?, APIError)

    var value: Value? {
        switch self {
        case .loaded(let v), .refreshing(let v): return v
        case .failed(let v, _): return v
        default: return nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        if case .refreshing = self { return true }
        return false
    }

    var error: APIError? {
        if case .failed(_, let e) = self { return e }
        return nil
    }

    static func == (lhs: LoadState<Value>, rhs: LoadState<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case (.loaded(let a), .loaded(let b)), (.refreshing(let a), .refreshing(let b)): return a == b
        case (.failed(let av, let ae), .failed(let bv, let be)): return av == bv && ae == be
        default: return false
        }
    }
}
