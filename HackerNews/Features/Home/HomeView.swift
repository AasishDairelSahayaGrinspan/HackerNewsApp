import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var connectivity: ConnectivityMonitor
    @State private var selectedStoryID: Int?
    @State private var searchText = ""
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                feedPicker
                OfflineBanner(isOffline: !connectivity.isOnline, lastFetched: viewModel.lastFetched)
                    .animation(reduceMotion ? nil : .easeInOut, value: connectivity.isOnline)

                content
            }
            .navigationTitle("Hacker News")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(FeedType.allCases) { feed in
                            Button {
                                SoundManager.playSelectionTick()
                                viewModel.selectedFeed = feed
                                HapticsManager.selectionChanged()
                            } label: {
                                Label(feed.rawValue, systemImage: feed.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Select feed")
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadInitial()
            }
            .onChange(of: viewModel.selectedFeed) { _, _ in
                Task { await viewModel.loadInitial() }
            }
            // Provide explicit debounced feed handling via viewModel.selectedFeed; HomeViewModel now coalesces via loadTask
            .navigationDestination(item: selectedStoryIDWrapper) { wrapper in
                StoryDetailView(storyID: wrapper.value)
            }
        }
    }

    private var feedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedType.allCases) { feed in
                    Button {
                        SoundManager.playSelectionTick()
                        viewModel.selectedFeed = feed
                        HapticsManager.selectionChanged()
                    } label: {
                        Label(feed.rawValue, systemImage: feed.icon)
                            .font(.subheadline.weight(viewModel.selectedFeed == feed ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedFeed == feed ? Color.orange : Color.secondary.opacity(0.12))
                            .foregroundStyle(viewModel.selectedFeed == feed ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .accessibilityAddTraits(viewModel.selectedFeed == feed ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading where viewModel.stories.isEmpty:
            List {
                ForEach(0..<8, id: \.self) { _ in SkeletonRow() }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .accessibilityLabel("Loading stories")

        case .failed(nil, let error):
            EmptyStateView(
                icon: "exclamationmark.triangle.fill",
                title: error.errorDescription ?? "Something went wrong",
                message: "Pull to refresh or check your connection.",
                actionTitle: "Retry",
                action: { Task { await viewModel.refresh() } }
            )

        case .failed(let cached, let error) where cached == nil || cached?.isEmpty == true:
            EmptyStateView(
                icon: "wifi.slash",
                title: "You're offline",
                message: error.errorDescription ?? "No cached content available.",
                actionTitle: "Retry",
                action: { Task { await viewModel.refresh() } }
            )

        default:
            if viewModel.stories.isEmpty {
                EmptyStateView(
                    icon: "newspaper",
                    title: "No stories yet",
                    message: "Pull down to refresh and load the latest stories from Hacker News.",
                    actionTitle: "Refresh",
                    action: { Task { await viewModel.refresh() } }
                )
            } else {
                List {
                    ForEach(viewModel.stories, id: \.id) { story in
                        StoryRowView(
                            story: story,
                            isSaved: viewModel.isSaved(story),
                            onSaveTap: { viewModel.toggleSave(story) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .onTapGesture {
                            SoundManager.playNavigationTap()
                            HapticsManager.lightImpact()
                            selectedStoryID = story.id
                        }
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentItem: story) }
                        }
                        // Divider
                        Divider().padding(.leading, 16)
                    }
                }
                .listStyle(.plain)
                .animation(reduceMotion ? nil : .default, value: viewModel.stories.map(\.id))
            }
        }
    }

    private var selectedStoryIDWrapper: Binding<IntWrapper?> {
        Binding(
            get: { selectedStoryID.map { IntWrapper(value: $0) } },
            set: { selectedStoryID = $0?.value }
        )
    }
}
