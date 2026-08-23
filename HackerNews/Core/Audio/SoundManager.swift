import Foundation
import AVFoundation
import UIKit

enum SoundManager {
    // MARK: - Existing semantic sounds
    @MainActor static func playSaveSound() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    @MainActor static func playUnsaveSound() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1105)
    }

    @MainActor static func playRefreshSound() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1054)
    }

    // MARK: - Universal button/navigation sounds
    /// Generic tap for any clickable button
    @MainActor static func playTap() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1102)
    }

    /// Navigation push (story row, saved row, search result)
    @MainActor static func playNavigationTap() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1103)
    }

    /// Light tick for collapse/expand, picker selection
    @MainActor static func playSelectionTick() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1156)
    }

    /// Destructive / clear action
    @MainActor static func playDestructive() {
        guard SettingsStore.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1053)
    }

    /// Backward-compatible alias used by legacy callers
    @MainActor static func playLightTick() { playSelectionTick() }
}
