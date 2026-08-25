import Foundation
import SwiftData
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var stories: [CachedStory] = []
    @Published var loadState: LoadState<[CachedStory]> = .idle
    @Published var selectedFeed: FeedType = .top
    @Published var isOfflineBannerVisible = false
    @Published var lastFetched: Date?

    private let repository: StoryRepositoryProtocol
    private var currentPage = 0
    private let pageSize = 30
    private var isLoadingMore = false
    private var loadTask: Task<Void, Never>?

    init(repository: StoryRepositoryProtocol? = nil) {
        if let repository {
            self.repository = repository
        } else {
            self.repository = StoryRepository()
        }
    }

    func loadInitial() async {
        loadTask?.cancel()
        // Use detached task so we can cancel coalescing feed switches
        await withCheckedContinuation { continuation in
            loadTask = Task { [weak self] in
                guard let self else { continuation.resume(); return }
                // Prevent overlapping loading states from racing
                if self.loadState == .loading {
                    // Allow reload if feed switched — reset
                    self.loadState = .loading
                } else {
                    self.loadState = .loading
                }
                let state = await self.repository.stories(for: self.selectedFeed, page: 0, pageSize: self.pageSize)
                if Task.isCancelled { continuation.resume(); return }
                self.handleState(state)
                self.currentPage = 0
                continuation.resume()
            }
        }
    }

    func refresh() async {
        loadTask?.cancel()
        await withCheckedContinuation { continuation in
            loadTask = Task { [weak self] in
                guard let self else { continuation.resume(); return }
                let prev = self.stories
                if !prev.isEmpty { self.loadState = .refreshing(prev) }
                else { self.loadState = .loading }
                let state = await self.repository.refresh(feed: self.selectedFeed)
                if Task.isCancelled { continuation.resume(); return }
                self.handleState(state)
                if !prev.isEmpty && state.value != nil {
                    HapticsManager.selectionChanged()
                    SoundManager.playRefreshSound()
                } else if case .failed(let cached, _) = state, (cached == nil || cached?.isEmpty == true) {
                    // Keep skeleton a bit longer? Already show failed view — no extra delay
                }
                continuation.resume()
            }
        }
    }

    func loadMoreIfNeeded(currentItem: CachedStory?) async {
        guard let currentItem, !isLoadingMore else { return }
        let thresholdIndex = stories.count - 5
        guard let idx = stories.firstIndex(where: { $0.id == currentItem.id }), idx >= thresholdIndex else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        currentPage += 1
        let state = await repository.stories(for: selectedFeed, page: currentPage, pageSize: pageSize)
        // stories are full list, so just update
        handleState(state)
    }

    private func handleState(_ state: LoadState<[CachedStory]>) {
        loadState = state
        switch state {
        case .loaded(let value), .refreshing(let value):
            stories = value
            lastFetched = Date()
            isOfflineBannerVisible = false
        case .failed(let value, let error):
            if let value, !value.isEmpty {
                stories = value
                isOfflineBannerVisible = true // show cached with error
            } else {
                stories = []
                isOfflineBannerVisible = true
            }
            // error handling could show banner
            _ = error
        case .loading:
            if stories.isEmpty {
                // show skeleton
            }
        case .idle: break
        }
    }

    func toggleSave(_ story: CachedStory) {
        let newState = repository.toggleSave(storyID: story.id)
        objectWillChange.send()
        // No need to refetch; persistence tracks saved
        _ = newState
    }

    func isSaved(_ story: CachedStory) -> Bool {
        repository.isSaved(storyID: story.id)
    }
}
