import Foundation
import Network
import Combine

@MainActor
final class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var isExpensive: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "connectivity")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }
}
