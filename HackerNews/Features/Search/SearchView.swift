import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedStoryID: Int?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.query.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Search cached stories", message: "Search finds titles, authors, domains and story text from stories you've already loaded. This is local search — no network search API is used, as the official HN API doesn't provide full-text search.")
                } else if viewModel.results.isEmpty {
                    EmptyStateView(icon: "doc.questionmark", title: "No results", message: "No cached stories match \"\(viewModel.query)\". Try a different keyword or load more stories from the News tab.")
                } else {
                    List {
                        Section(header: Text("Search cached stories · \(viewModel.results.count) results").font(.caption)) {
                            ForEach(viewModel.results, id: \.id) { story in
                                StoryRowView(story: story, isSaved: viewModel.isSaved(story), onSaveTap: { viewModel.toggleSave(story) })
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .onTapGesture { selectedStoryID = story.id }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .animation(reduceMotion ? nil : .default, value: viewModel.results.map(\.id))
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Search titles, authors, domains")
            .navigationDestination(item: selectedWrapper) { w in
                StoryDetailView(storyID: w.value)
            }
        }
    }

    private var selectedWrapper: Binding<IntWrapper?> {
        Binding(get: { selectedStoryID.map { IntWrapper(value: $0) } }, set: { selectedStoryID = $0?.value })
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet { performSearch() }
    }
    @Published var results: [CachedStory] = []

    private let repo: StoryRepositoryProtocol

    init(repo: StoryRepositoryProtocol? = nil) {
        if let repo { self.repo = repo } else { self.repo = StoryRepository() }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        results = repo.search(query: trimmed)
    }

    func isSaved(_ story: CachedStory) -> Bool { repo.isSaved(storyID: story.id) }
    func toggleSave(_ story: CachedStory) { _ = repo.toggleSave(storyID: story.id); objectWillChange.send() }
}
