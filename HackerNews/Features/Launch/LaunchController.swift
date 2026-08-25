import SwiftUI
import UIKit

/// Controls intelligent launch behavior: always shows a premium animation,
/// but adapts duration — cold = full cinematic ~1050ms, warm = quick 600ms,
/// reduce-motion/low-power = minimal fade. Also fixes “not showing on open/close”
/// by resetting state on every foreground (not just first cold launch).
@MainActor
final class LaunchController: ObservableObject {
    @Published var shouldShowAnimation: Bool = false
    @Published var finished: Bool = false
    @Published var isWarm: Bool = false

    private let lastBackgroundKey = "HNLastBackgroundDate"
    private let warmThreshold: TimeInterval = 8 // seconds — reopen quickly = warm quick animation

    init() {
        // Cold launch: always show (supports icon→launch continuity every install)
        trigger(showWarm: false)
    }

    /// Called on scenePhase .background
    func markBackgrounded() {
        UserDefaults.standard.set(Date(), forKey: lastBackgroundKey)
    }

    /// Called on scenePhase .active (foreground). Resets overlay so every open/close
    /// reliably shows an animation — warm gets quick variant, cold gets full.
    func markForegrounded() {
        let last = UserDefaults.standard.object(forKey: lastBackgroundKey) as? Date
        let sinceBG = last.map { Date().timeIntervalSince($0) } ?? 9999
        let warm = sinceBG < 300 // <5min counts as warm for duration choice, but we still show
        // Very quick background→foreground (<8s) is typical “open/close” — show warm quick
        // Even so, we *always* show something so user never sees inconsistent skip
        isWarm = warm
        trigger(showWarm: warm)
    }

    private func trigger(showWarm: Bool) {
        // Respect reduceMotion/lowPower still shows but view will render reduced path
        isWarm = showWarm
        finished = false
        shouldShowAnimation = true
    }

    func complete() {
        // Animate out then keep finished until next foreground trigger
        withAnimation(.easeOut(duration: 0.20)) {
            finished = true
        }
        // Keep shouldShow true until transition finishes, then flip
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.shouldShowAnimation = false
        }
    }
}
