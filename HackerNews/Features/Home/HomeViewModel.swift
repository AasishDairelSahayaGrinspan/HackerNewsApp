import Foundation
import Combine

/// Feed view model. It no longer owns a repository, pagination cursor or
/// cache policy: it mirrors the engine's feed snapshot and forwards intents.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var stories: [Story] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var selectedFeed: FeedType = .top
    @Published private(set) var isOffline = false
    @Published private(set) var isStale = false
    @Published private(set) var lastFetched: Date?
    @Published private(set) var errorMessage: String?

    private let client: AppBackend
    private var cancellables = Set<AnyCancellable>()
    private var lastLoadMoreTriggerCount = -1
    private var hasStarted = false

    init(client: AppBackend? = nil) {
        let backend = client ?? .shared
        self.client = backend
        backend.$feed
            .sink { [weak self] snapshot in
                self?.apply(snapshot)
            }
            .store(in: &cancellables)
        apply(backend.feed)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        client.start()
        client.selectFeed(selectedFeed)
    }

    func selectFeed(_ feed: FeedType) {
        guard feed != selectedFeed else { return }
        selectedFeed = feed
        lastLoadMoreTriggerCount = -1
        client.selectFeed(feed)
    }

    func refresh() async {
        let startRevision = client.feed.revision
        client.refreshFeed()
        HapticsManager.selectionChanged()
        SoundManager.playRefreshSound()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [client] in
                for await snapshot in await client.feedUpdates() {
                    if snapshot.revision > startRevision,
                       snapshot.phase == .loaded || snapshot.phase == .failed {
                        break
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
            await group.next()
            group.cancelAll()
        }
    }

    func loadMoreIfNeeded(currentItem: Story?) {
        guard let currentItem, !stories.isEmpty else { return }
        let threshold = max(0, stories.count - 5)
        guard let index = stories.firstIndex(where: { $0.id == currentItem.id }),
              index >= threshold else { return }
        guard stories.count != lastLoadMoreTriggerCount else { return }
        lastLoadMoreTriggerCount = stories.count
        client.loadMore()
    }

    func toggleSave(_ story: Story) {
        client.toggleSave(story.id)
        if story.isSaved {
            SoundManager.playUnsaveSound()
        } else {
            SoundManager.playSaveSound()
        }
        HapticsManager.lightImpact()
    }

    func isSaved(_ story: Story) -> Bool {
        story.isSaved
    }

    private func apply(_ snapshot: FeedSnapshotModel) {
        selectedFeed = snapshot.feed
        stories = snapshot.stories
        phase = snapshot.phase
        isOffline = snapshot.offline
        isStale = snapshot.stale
        lastFetched = snapshot.lastSyncAt
        errorMessage = snapshot.error?.message
        if snapshot.phase == .loading || snapshot.phase == .refreshing {
            lastLoadMoreTriggerCount = -1
        }
    }
}
