import Foundation
import UIKit

enum HapticsManager {
    @MainActor static func selectionChanged() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
    }

    @MainActor static func lightImpact() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
    }

    @MainActor static func success() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }

    @MainActor static func error() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    enum Appearance: String, CaseIterable {
        case system, light, dark
    }

    private init() {
        self.hapticsEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        self.appearance = Appearance(rawValue: raw) ?? .system
    }
}
