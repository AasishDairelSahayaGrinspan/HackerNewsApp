import SwiftUI

struct SavedView: View {
    @StateObject private var viewModel = SavedViewModel()
    @State private var selectedStoryID: Int?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.savedStories.isEmpty {
                    EmptyStateView(
                        icon: "bookmark.slash",
                        title: "No saved stories",
                        message: "Tap the bookmark icon on any story to save it for offline reading. Saved stories stay on your device even without internet."
                    )
                } else if viewModel.filtered.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results", message: "No saved stories match \"\(viewModel.searchText)\".")
                } else {
                    List {
                        ForEach(viewModel.filtered, id: \.storyID) { saved in
                            let cached = viewModel.cachedStories[saved.storyID]
                            SavedRow(saved: saved, cached: cached)
                                .onTapGesture { selectedStoryID = saved.storyID }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                            viewModel.unsave(saved)
                                        }
                                    } label: {
                                        Label("Unsave", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .animation(reduceMotion ? nil : .default, value: viewModel.savedStories.map(\.storyID))
                }
            }
            .navigationTitle("Saved")
            .searchable(text: $viewModel.searchText, prompt: "Search saved stories")
            .toolbar {
                if !viewModel.savedStories.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(viewModel.savedStories.count) saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear { viewModel.refresh() }
            .navigationDestination(item: selectedWrapper) { w in
                StoryDetailView(storyID: w.value)
            }
        }
    }

    private var selectedWrapper: Binding<IntWrapper?> {
        Binding(
            get: { selectedStoryID.map { IntWrapper(value: $0) } },
            set: { selectedStoryID = $0?.value }
        )
    }
}

private struct SavedRow: View {
    let saved: SavedStory
    let cached: CachedStory?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cached?.title ?? saved.title ?? "Story #\(saved.storyID)")
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let author = cached?.author ?? saved.author {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                }
                Text(saved.savedAt.timeAgoDisplay())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let score = cached?.score ?? (saved.score != 0 ? saved.score : nil) {
                    Text("· \(score) points").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let domain = cached?.domain ?? (saved.url.flatMap { URL(string: $0)?.host }) {
                Text(domain.replacingOccurrences(of: "www.", with: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
