import SwiftUI
import SafariServices

struct StoryDetailView: View {
    let storyID: Int
    @StateObject private var viewModel: StoryDetailViewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var showShareSheet = false

    init(storyID: Int) {
        self.storyID = storyID
        _viewModel = StateObject(wrappedValue: StoryDetailViewModel(storyID: storyID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let story = viewModel.story {
                    header(story: story)
                    if let text = story.text, !text.isEmpty {
                        Text(text.hnAttributedString)
                            .font(.body)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                            .textSelection(.enabled)
                    }
                    actionBar(story: story)
                    Divider().padding(.horizontal, 16)

                    // Polish: progressive skeletons + streaming footer
                    if viewModel.isLoadingComments && viewModel.comments.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                        }
                        .accessibilityLabel("Loading comments")
                    } else if viewModel.comments.isEmpty {
                        EmptyStateView(icon: "bubble.left", title: "No comments", message: "Be the first to share your thoughts on Hacker News.")
                    } else {
                        HStack {
                            Text("\(viewModel.comments.count) threads · \(totalCommentCount) comments")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if viewModel.isLoadingComments {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading…")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.isLoadingComments)

                        CommentTreeView(nodes: $viewModel.comments)
                            .padding(.bottom, 8)

                        if viewModel.isLoadingComments {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Fetching replies…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                            .accessibilityLabel("Loading more comments")
                        }
                    }
                } else if viewModel.isLoadingStory {
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                    }
                    .padding(.top, 16)
                } else {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "Failed to load", message: viewModel.errorMessage ?? "Couldn't reach Hacker News. Check your connection and try again.", actionTitle: "Retry") {
                        SoundManager.playTap()
                        Task { await viewModel.load() }
                    }
                    .task {
                        // Auto-retry once after 1.2s if we landed on failed with no story (transient)
                        if viewModel.story == nil && !viewModel.isLoadingStory {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            if viewModel.story == nil && viewModel.errorMessage != nil { await viewModel.load() }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        // Sound + haptics handled inside toggleSave -> playSave/Unsave
                        viewModel.toggleSave()
                    } label: {
                        Image(systemName: viewModel.isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(viewModel.isSaved ? .orange : .primary)
                    }
                    .accessibilityLabel(viewModel.isSaved ? "Unsave" : "Save")

                    if viewModel.shareURL() != nil {
                        Button {
                            SoundManager.playTap()
                            HapticsManager.lightImpact()
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share story")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showSafari) {
            if let urlStr = viewModel.story?.url, let url = URL(string: urlStr) {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.shareURL() {
                ShareSheet(url: url)
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private func header(story: CachedStory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(story.title ?? "(No title)")
                .font(.title3.weight(.bold))
                .lineSpacing(2)

            HStack(spacing: 6) {
                if let domain = story.domain {
                    Text(domain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Label("\(story.score) points", systemImage: "arrow.up.circle.fill")
                Text("·")
                Label(story.author ?? "unknown", systemImage: "person.fill")
                if let date = story.createdAt {
                    Text("· \(date.timeAgoDisplay())")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if story.url != nil {
                Button {
                    SoundManager.playNavigationTap()
                    viewModel.showSafari = true
                    HapticsManager.lightImpact()
                } label: {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Open Article")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
    }

    private func actionBar(story: CachedStory) -> some View {
        HStack(spacing: 16) {
            Label("\(story.commentCount) comments", systemImage: "bubble.left.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("hn · \(story.id)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var totalCommentCount: Int {
        func count(_ nodes: [CommentNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + count($1.children) }
        }
        return count(viewModel.comments)
    }
}

// MARK: - SafariView
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
