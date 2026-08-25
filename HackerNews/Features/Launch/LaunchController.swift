import SwiftUI
import UIKit

/// Controls intelligent launch behavior: cold vs warm, Reduce Motion, Low Power.
@MainActor
final class LaunchController: ObservableObject {
    @Published var shouldShowAnimation: Bool = false
    @Published var finished: Bool = false

    private let coldLaunchThreshold: TimeInterval = 300 // 5 min
    private let lastBackgroundKey = "HNLastBackgroundDate"
    private let hasLaunchedKey = "HNHasColdLaunched"

    init() {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        // Low power is not fatal but we simplify if enabled
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isCold: Bool
        if UserDefaults.standard.object(forKey: hasLaunchedKey) == nil {
            isCold = true
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        } else if let last = UserDefaults.standard.object(forKey: lastBackgroundKey) as? Date {
            isCold = Date().timeIntervalSince(last) > coldLaunchThreshold
        } else {
            isCold = true
        }
        // Always show on very first cold launch even with low power (but simplified)
        // For warm resumed launches within threshold, skip long animation
        if isCold && !reduceMotion {
            shouldShowAnimation = true
        } else if isCold && reduceMotion {
            shouldShowAnimation = true // but will render simplified path
        } else {
            shouldShowAnimation = false
            finished = true
        }
        // Log for debugging
        if lowPower && shouldShowAnimation {
            // keep but view will auto-simplify if reduceMotion false? lowPower degrades to simpler timing
        }
    }

    func markBackgrounded() {
        UserDefaults.standard.set(Date(), forKey: lastBackgroundKey)
    }

    func complete() {
        withAnimation(.easeOut(duration: 0.22)) {
            finished = true
        }
        shouldShowAnimation = false
    }
}
