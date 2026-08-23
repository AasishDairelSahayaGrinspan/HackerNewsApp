import Foundation
import AVFoundation
import UIKit

enum SoundManager {
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
}
