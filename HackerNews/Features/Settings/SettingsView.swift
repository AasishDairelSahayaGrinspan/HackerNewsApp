import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var showClearConfirm = false
    @State private var clearMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $settings.appearance) {
                        Text("System").tag(SettingsStore.Appearance.system)
                        Text("Light").tag(SettingsStore.Appearance.light)
                        Text("Dark").tag(SettingsStore.Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .onChange(of: settings.appearance) { _, _ in
                        SoundManager.playSelectionTick()
                        HapticsManager.selectionChanged()
                    }
                }

                Section(header: Text("Feedback")) {
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .onChange(of: settings.hapticsEnabled) { _, _ in
                        HapticsManager.lightImpact()
                        SoundManager.playTap()
                    }
                    Toggle(isOn: $settings.soundEnabled) {
                        Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                    }
                    .onChange(of: settings.soundEnabled) { _, newValue in
                        if newValue { SoundManager.playTap() }
                        HapticsManager.lightImpact()
                    }
                }

                Section(header: Text("Content")) {
                    Button(role: .destructive) {
                        SoundManager.playTap()
                        HapticsManager.lightImpact()
                        showClearConfirm = true
                    } label: {
                        Label("Clear Cache (Keep Saved)", systemImage: "trash")
                    }
                    Button(role: .destructive) {
                        SoundManager.playDestructive()
                        PersistenceController.shared.clearAllCache(keepSaved: false)
                        clearMessage = "All data cleared."
                        HapticsManager.success()
                    } label: {
                        Label("Clear Everything Including Saved", systemImage: "trash.fill")
                    }
                    if let msg = clearMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://news.ycombinator.com")!) {
                        HStack {
                            Text("Hacker News")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { SoundManager.playNavigationTap() })
                    Link(destination: URL(string: "https://github.com/HackerNews/API")!) {
                        HStack {
                            Text("API Documentation")
                            Spacer()
                            Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { SoundManager.playNavigationTap() })
                    Text("Built with SwiftUI, SwiftData, and the official Hacker News Firebase API. No tracking, no accounts required. Content © Y Combinator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Clear cache?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    SoundManager.playDestructive()
                    PersistenceController.shared.clearAllCache(keepSaved: true)
                    clearMessage = "Cache cleared. Saved stories kept."
                    HapticsManager.success()
                }
                Button("Cancel", role: .cancel) {
                    SoundManager.playTap()
                }
            } message: {
                Text("This removes cached feeds and comments but keeps your saved stories.")
            }
        }
    }
}

#Preview {
    SettingsView().environmentObject(SettingsStore.shared)
}
