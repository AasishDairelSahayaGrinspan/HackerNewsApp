import Foundation
import Combine

/// Story detail view model. Story and comment trees are engine snapshots;
/// only collapse state and sheet presentation live here.
@MainActor
final class StoryDetailViewModel: ObservableObject {
    @Published private(set) var story: Story?
    @Published var comments: [CommentNode] = []
    @Published private(set) var isLoadingStory = false
    @Published private(set) var isLoadingComments = false
    @Published private(set) var commentsComplete = false
    @Published private(set) var commentTotal = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaved = false
    @Published var showSafari = false

    private let storyID: Int
    private let client: EngineClient
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    init(storyID: Int, client: EngineClient = .shared) {
        self.storyID = storyID
        self.client = client

        client.$storySnapshots
            .compactMap { $0[storyID] }
            .sink { [weak self] snapshot in
                self?.applyStory(snapshot)
            }
            .store(in: &cancellables)

        client.$commentsSnapshots
            .compactMap { $0[storyID] }
            .sink { [weak self] snapshot in
                self?.applyComments(snapshot)
            }
            .store(in: &cancellables)

        client.$savedStories
            .sink { [weak self] saved in
                guard let self else { return }
                self.isSaved = saved.contains { $0.storyID == self.storyID }
            }
            .store(in: &cancellables)

        if let snapshot = client.storySnapshot(for: storyID) {
            applyStory(snapshot)
        }
        if let snapshot = client.commentsSnapshot(for: storyID) {
            applyComments(snapshot)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        client.openStory(storyID)
        client.loadComments(for: storyID, force: false)
    }

    func refresh() async {
        client.refreshStory(storyID)
        client.loadComments(for: storyID, force: true)
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    func toggleSave() {
        guard story != nil else { return }
        isSaved.toggle()
        client.toggleSave(storyID)
        if isSaved {
            SoundManager.playSaveSound()
        } else {
            SoundManager.playUnsaveSound()
        }
        HapticsManager.lightImpact()
    }

    func shareURL() -> URL? {
        guard let story else { return nil }
        if let urlString = story.url, let url = URL(string: urlString) { return url }
        return URL(string: "https://news.ycombinator.com/item?id=\(story.id)")
    }

    private func applyStory(_ snapshot: StorySnapshotModel) {
        story = snapshot.story
        isLoadingStory = snapshot.phase == .loading || snapshot.phase == .refreshing
        if let story {
            isSaved = story.isSaved
        }
        if let error = snapshot.error, snapshot.story == nil {
            errorMessage = error.message
        } else {
            errorMessage = nil
        }
    }

    private func applyComments(_ snapshot: CommentsSnapshotModel) {
        var collapsed = Set<Int>()
        for node in comments {
            node.collectCollapsed(into: &collapsed)
        }
        comments = snapshot.roots.map { $0.applyingCollapsed(collapsed) }
        isLoadingComments = snapshot.loading
        commentsComplete = snapshot.complete
        commentTotal = snapshot.totalLoaded
        if let error = snapshot.error {
            errorMessage = error.message
        }
    }
}
