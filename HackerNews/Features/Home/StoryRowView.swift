import SwiftUI

struct StoryRowView: View {
    let story: CachedStory
    var isSaved: Bool
    var onSaveTap: () -> Void
    var onShareTap: (() -> Void)?

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(story.title ?? "(No title)")
                    .font(.headline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(story.isDead || story.isHnDeleted ? .secondary : .primary)
                Spacer()
                Button(action: onSaveTap) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isSaved ? .orange : .secondary)
                        .font(.system(size: 16, weight: .medium))
                        .contentShape(Rectangle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "Unsave story" : "Save story")
                .accessibilityAddTraits(.isButton)
            }

            if let text = story.text, !text.isEmpty, story.url == nil {
                Text(text.strippedHTML)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                if let domain = story.domain {
                    Text(domain)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.secondary)
                }
                Text("\(story.score.abbreviatedScore) points")
                Text("·")
                if let date = story.createdAt {
                    Text(date.timeAgoDisplay())
                }
                Text("·")
                Text("\(story.commentCount) comments")
                    .foregroundStyle(.orange)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 6) {
                if let author = story.author {
                    Label(author, systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if story.isDead {
                    Text("dead")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
                if story.isHnDeleted {
                    Text("deleted")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(story.title ?? ""), \(story.score) points, by \(story.author ?? "unknown"), \(story.commentCount) comments")
        .accessibilityHint("Double tap to open story detail")
    }
}

#Preview {
    let s = CachedStory(id: 123, title: "OpenAI releases new model that can reason across images and text with stunning performance", author: "dhouston", createdAt: Date().addingTimeInterval(-3600*4), score: 342, url: "https://example.com", commentCount: 87)
    StoryRowView(story: s, isSaved: false, onSaveTap: {})
}
