import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var engine: EngineClient
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
                        engine.clearCache(keepSaved: false)
                        clearMessage = "All data cleared."
                        HapticsManager.success()
                    } label: {
                        Label("Clear Everything Including Saved", systemImage: "trash.fill")
                    }
                    if let msg = clearMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Core", value: engine.status.coreVersion)
                    LabeledContent("Cached stories", value: "\(engine.status.cachedStories)")
                    LabeledContent("Cached comments", value: "\(engine.status.cachedComments)")
                    LabeledContent("Saved stories", value: "\(engine.status.savedCount)")
                    LabeledContent("Search documents", value: "\(engine.status.searchDocs)")
                    LabeledContent("Database", value: engine.status.formattedDatabaseSize)
                    LabeledContent("Network requests", value: "\(engine.status.metrics.requests)")
                    LabeledContent("Retries", value: "\(engine.status.metrics.retries)")
                    LabeledContent("Cache hit rate", value: cacheHitRate)
                    LabeledContent("Average latency", value: averageLatency)
                    LabeledContent("Snapshots emitted", value: "\(engine.status.metrics.snapshotsEmitted)")
                    LabeledContent("Uptime", value: uptime)
                } header: {
                    Text("Engine")
                } footer: {
                    Text("C++20 event loop · SQLite write-behind · local search index")
                        .font(.caption2)
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
                    Text("SwiftUI renders the interface. A native C++ engine owns networking, persistence, caching, comment traversal and search. No tracking, no accounts required. Content © Y Combinator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Clear cache?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    SoundManager.playDestructive()
                    engine.clearCache(keepSaved: true)
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

    private var cacheHitRate: String {
        let rate = engine.status.metrics.cacheHitRate
        return rate == 0 ? "—" : String(format: "%.0f%%", rate * 100)
    }

    private var averageLatency: String {
        let latency = engine.status.metrics.averageLatencyMs
        return latency == 0 ? "—" : String(format: "%.0f ms", latency)
    }

    private var uptime: String {
        let seconds = Int(engine.status.uptimeSeconds)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore.shared)
        .environmentObject(EngineClient.shared)
}
