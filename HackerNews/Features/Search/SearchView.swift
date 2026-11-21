import SwiftUI
import Combine

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedStoryID: Int?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.query.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Search cached stories", message: "Search finds titles, authors, domains and story text from stories you've already loaded. The engine keeps a local inverted index — no network search API is used, as the official HN API doesn't provide full-text search.")
                } else if viewModel.results.isEmpty {
                    EmptyStateView(icon: "doc.questionmark", title: "No results", message: "No cached stories match \"\(viewModel.query)\". Try a different keyword or load more stories from the News tab.")
                } else {
                    List {
                        Section(header: Text("Search cached stories · \(viewModel.results.count) results").font(.caption)) {
                            ForEach(viewModel.results) { story in
                                StoryRowView(story: story,
                                             isSaved: story.isSaved,
                                             onSaveTap: { viewModel.toggleSave(story) })
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .onTapGesture {
                                        SoundManager.playNavigationTap()
                                        HapticsManager.lightImpact()
                                        selectedStoryID = story.id
                                    }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .animation(reduceMotion ? nil : .default, value: viewModel.results.map(\.id))
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Search titles, authors, domains")
            .navigationDestination(item: selectedWrapper) { wrapper in
                StoryDetailView(storyID: wrapper.value)
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
    @Published private(set) var results: [Story] = []

    private let client: EngineClient
    private var cancellables = Set<AnyCancellable>()

    init(client: EngineClient = .shared) {
        self.client = client
        client.$savedStories
            .sink { [weak self] saved in
                guard let self else { return }
                let ids = Set(saved.map(\.storyID))
                self.results = self.results.map { $0.withSaved(ids.contains($0.id)) }
            }
            .store(in: &cancellables)
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        results = client.search(trimmed)
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
}
