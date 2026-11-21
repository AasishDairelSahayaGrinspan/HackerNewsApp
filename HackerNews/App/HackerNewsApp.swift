import SwiftUI

@main
struct HackerNewsApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var engine: EngineClient
    @StateObject private var launchController = LaunchController()
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        let settingsStore = SettingsStore.shared
        let engineClient = EngineClient.shared
        _settings = StateObject(wrappedValue: settingsStore)
        _engine = StateObject(wrappedValue: engineClient)
        _launchController = StateObject(wrappedValue: LaunchController())
        engineClient.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environmentObject(settings)
                    .environmentObject(engine)
                    .preferredColorScheme(colorScheme)
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        engine.evictCache()
                    }

                // X-style 3D launch overlay — icon→3D→UI continuity
                if launchController.shouldShowAnimation && !launchController.finished {
                    LaunchAnimationView {
                        launchController.complete()
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    engine.evictCache()
                }
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "hnreader",
              url.host == "story",
              let idString = url.pathComponents.last,
              let id = Int(idString) else { return }
        NotificationCenter.default.post(name: .openStoryDeepLink, object: id)
    }
}

extension Notification.Name {
    static let openStoryDeepLink = Notification.Name("openStoryDeepLink")
}

struct RootTabView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedTab = 0
    @State private var deepLinkStoryID: Int?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("News", systemImage: "newspaper.fill") }
                .tag(0)

            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark.fill") }
                .tag(1)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.orange)
        .onChange(of: selectedTab) { _, _ in
            SoundManager.playSelectionTick()
            HapticsManager.selectionChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openStoryDeepLink)) { notification in
            if let id = notification.object as? Int {
                SoundManager.playNavigationTap()
                deepLinkStoryID = id
                selectedTab = 0
            }
        }
        .sheet(item: deepLinkStoryIDWrapper) { wrapper in
            NavigationStack {
                StoryDetailView(storyID: wrapper.value)
            }
        }
    }

    private var deepLinkStoryIDWrapper: Binding<IntWrapper?> {
        Binding(
            get: { deepLinkStoryID.map { IntWrapper(value: $0) } },
            set: { deepLinkStoryID = $0?.value }
        )
    }
}

struct IntWrapper: Identifiable, Hashable {
    var id: Int { value }
    let value: Int
}
