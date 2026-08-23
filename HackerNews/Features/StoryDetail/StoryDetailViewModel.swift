import Foundation

@MainActor
final class StoryDetailViewModel: ObservableObject {
    @Published var story: CachedStory?
    @Published var comments: [CommentNode] = []
    @Published var isLoadingStory = false
    @Published var isLoadingComments = false
    @Published var errorMessage: String?
    @Published var isSaved = false
    @Published var showSafari = false

    private let storyID: Int
    private let storyRepo: StoryRepositoryProtocol
    private let commentRepo: CommentRepository
    private let persistence: PersistenceController

    init(storyID: Int,
         storyRepo: StoryRepositoryProtocol? = nil,
         commentRepo: CommentRepository? = nil,
         persistence: PersistenceController? = nil) {
        self.storyID = storyID
        self.storyRepo = storyRepo ?? StoryRepository()
        self.commentRepo = commentRepo ?? CommentRepository()
        self.persistence = persistence ?? PersistenceController.shared
    }

    func load() async {
        isLoadingStory = true
        defer { isLoadingStory = false }
        do {
            let s = try await storyRepo.fetchStory(id: storyID)
            story = s
            isSaved = persistence.isSaved(storyID: s.id)
            await loadComments()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            if let cached = persistence.fetchCachedStory(id: storyID) {
                story = cached
                isSaved = persistence.isSaved(storyID: cached.id)
                await loadComments()
            }
        }
    }

    func loadComments() async {
        guard let story else { return }
        isLoadingComments = true
        defer { isLoadingComments = false }

        // Offline-first: show cached instantly (no network)
        let cached = persistence.fetchComments(for: story.id)
        if !cached.isEmpty {
            comments = commentRepo.buildTree(comments: cached, rootKids: nil)
            // Trigger background refresh without blocking UI
            Task { _ = await self.commentRepo.loadComments(for: story) }
            return
        }

        // No cache: progressive streaming - 30 in <1s, then rest, handles 1313 descendant stories
        await commentRepo.loadCommentsStreaming(for: story) { [weak self] nodes in
            guard let self else { return }
            self.comments = nodes
        }

        if comments.isEmpty {
            // Fallback full load (e.g., kids empty or streaming failed)
            comments = await commentRepo.loadComments(for: story)
        }
    }

    func toggleSave() {
        guard let story else { return }
        isSaved = storyRepo.toggleSave(storyID: story.id)
        objectWillChange.send()
    }

    func shareURL() -> URL? {
        guard let story else { return nil }
        if let urlStr = story.url, let url = URL(string: urlStr) { return url }
        return URL(string: "https://news.ycombinator.com/item?id=\(story.id)")
    }
}
