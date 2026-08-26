import SwiftUI
import UIKit

/// Option A: Show splash only once ever (first install) — never again until reinstall.
/// No every-open trigger. Fixes “everytime showing splash don't do that”.
@MainActor
final class LaunchController: ObservableObject {
    @Published var shouldShowAnimation: Bool = false
    @Published var finished: Bool = false
    @Published var isWarm: Bool = false

    private let hasShownKey = "HNSplashShownOnce_v2"

    init() {
        // Once-ever: if we've shown once, never again
        if UserDefaults.standard.bool(forKey: hasShownKey) {
            shouldShowAnimation = false
            finished = true
        } else {
            // First launch ever — show the single Y zoom
            isWarm = false
            finished = false
            shouldShowAnimation = true
        }
    }

    /// No-op now — kept for HackerNewsApp calls but does not re-trigger
    func markBackgrounded() {}
    func markForegrounded() {}

    func complete() {
        // Persist that we've shown once forever
        UserDefaults.standard.set(true, forKey: hasShownKey)
        withAnimation(.easeOut(duration: 0.20)) {
            finished = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.shouldShowAnimation = false
        }
    }
}
