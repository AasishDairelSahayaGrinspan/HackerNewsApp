import SwiftUI
import UIKit

/// X-style: show splash on every cold start (not once-ever).
/// X holds black + centered logo ~1s on each open, then cuts to feed.
@MainActor
final class LaunchController: ObservableObject {
    @Published var shouldShowAnimation: Bool = true
    @Published var finished: Bool = false

    init() {
        // Every cold start shows the X-style splash.
        shouldShowAnimation = true
        finished = false
    }

    func complete() {
        withAnimation(.easeOut(duration: 0.20)) {
            finished = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.shouldShowAnimation = false
        }
    }
}
