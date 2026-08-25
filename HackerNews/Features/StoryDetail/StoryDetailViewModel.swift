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
        // Retry with backoff for transient Firebase hiccups (prevents cold 'Failed to load')
        var lastErr: Error?
        var s: CachedStory?
        for attempt in 0...2 {
            do {
                s = try await storyRepo.fetchStory(id: storyID)
                break
            } catch {
                lastErr = error
                if let api = error as? APIError, !api.isRetryable || attempt == 2 { break }
                // Also map non-APIError retryable via APIError.map
                let mapped = APIError.map(error)
                if !mapped.isRetryable || attempt == 2 { break }
                let backoff: UInt64 = attempt == 0 ? 500_000_000 : 900_000_000
                try? await Task.sleep(nanoseconds: backoff)
                if Task.isCancelled { break }
            }
        }
        if let resolved = s {
            story = resolved
            isSaved = persistence.isSaved(storyID: resolved.id)
            errorMessage = nil
            await loadComments()
            return
        }
        // Fallback to cached story if network ultimately failed
        if let cached = persistence.fetchCachedStory(id: storyID) {
            story = cached
            isSaved = persistence.isSaved(storyID: cached.id)
            errorMessage = nil
            await loadComments()
            return
        }
        errorMessage = (lastErr as? APIError)?.errorDescription ?? lastErr?.localizedDescription ?? "Unknown error"
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
