import SwiftUI

struct CommentRowView: View {
    let node: CommentNode
    var onToggleCollapse: () -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(node.comment.author ?? "unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                if let date = node.comment.createdAt {
                    Text(date.timeAgoDisplay())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !node.children.isEmpty {
                    Button(action: onToggleCollapse) {
                        Image(systemName: node.isCollapsed ? "chevron.right.circle.fill" : "chevron.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(node.isCollapsed ? "Expand replies" : "Collapse replies")
                }
            }

            if node.comment.isHnDeleted {
                Text("[deleted]")
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
            } else if node.comment.isDead {
                Text("[dead]")
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
            } else if let text = node.comment.text {
                Text(text.hnAttributedString)
                    .font(.subheadline)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }

            if !node.children.isEmpty && node.isCollapsed {
                Text("\(node.children.count) repl\(node.children.count == 1 ? "y" : "ies") hidden")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .padding(.leading, CGFloat(node.depth) * 12)
        .overlay(alignment: .leading) {
            if node.depth > 0 {
                Rectangle()
                    .fill(Color.orange.opacity(0.25))
                    .frame(width: 2)
                    .padding(.vertical, 4)
                    .padding(.leading, CGFloat(node.depth) * 12 - 8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CommentTreeView: View {
    @Binding var nodes: [CommentNode]
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(flatNodes) { node in
                CommentRowView(node: node) {
                    toggle(nodeID: node.id)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: nodes)
            }
        }
        .padding(.horizontal, 16)
    }

    // Flatten tree respecting collapsed state
    private var flatNodes: [CommentNode] {
        var result: [CommentNode] = []
        func traverse(_ ns: [CommentNode]) {
            for n in ns {
                result.append(n)
                if !n.isCollapsed {
                    traverse(n.children)
                }
            }
        }
        traverse(nodes)
        return result
    }

    private func toggle(nodeID: Int) {
        func recurse(_ ns: inout [CommentNode]) -> Bool {
            for i in ns.indices {
                if ns[i].id == nodeID {
                    ns[i].isCollapsed.toggle()
                    HapticsManager.lightImpact()
                    return true
                }
                if recurse(&ns[i].children) { return true }
            }
            return false
        }
        _ = recurse(&nodes)
    }
}
