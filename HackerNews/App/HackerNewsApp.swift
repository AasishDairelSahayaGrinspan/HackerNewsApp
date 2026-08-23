import SwiftUI
import SwiftData

@main
struct HackerNewsApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var connectivity: ConnectivityMonitor
    let persistence: PersistenceController

    @MainActor
    init() {
        // MainActor isolated shared access
        let s = SettingsStore.shared
        let c = ConnectivityMonitor.shared
        let p = PersistenceController.shared
        _settings = StateObject(wrappedValue: s)
        _connectivity = StateObject(wrappedValue: c)
        persistence = p
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(connectivity)
                .modelContainer(persistence.container)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        persistence.evictExpiredCache()
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
        guard url.scheme == "hnreader", url.host == "story", let idStr = url.pathComponents.last, let id = Int(idStr) else { return }
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
        .onReceive(NotificationCenter.default.publisher(for: .openStoryDeepLink)) { notif in
            if let id = notif.object as? Int {
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
    let id = UUID()
    let value: Int
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: IntWrapper, rhs: IntWrapper) -> Bool { lhs.id == rhs.id }
}
