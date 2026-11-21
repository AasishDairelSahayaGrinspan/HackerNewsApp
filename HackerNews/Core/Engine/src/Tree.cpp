#include "hn/Tree.hpp"

#include <unordered_map>
#include <unordered_set>

namespace hn {

namespace {

CommentNode buildNode(int id,
                      int depth,
                      int maxDepth,
                      const std::unordered_map<int, const Comment*>& byId,
                      std::unordered_set<int>& path) {
    CommentNode node;
    const auto it = byId.find(id);
    if (it == byId.end()) return node;
    if (path.count(id)) return node; // cycle: stop before re-adding the node
    node.comment = *it->second;
    node.depth = depth;

    if (depth >= maxDepth) return node;
    path.insert(id);

    node.children.reserve(node.comment.kids.size());
    for (int childId : node.comment.kids) {
        if (childId == id) continue;
        if (byId.find(childId) == byId.end()) continue;
        CommentNode child = buildNode(childId, depth + 1, maxDepth, byId, path);
        if (child.comment.id != 0) node.children.push_back(std::move(child));
    }

    path.erase(id);
    return node;
}

} // namespace

std::vector<CommentNode> buildCommentTree(const std::vector<Comment>& comments,
                                          const std::vector<int>& rootKids,
                                          int maxDepth) {
    if (comments.empty()) return {};

    std::unordered_map<int, const Comment*> byId;
    byId.reserve(comments.size() * 2);
    for (const auto& comment : comments) byId[comment.id] = &comment;

    std::vector<int> roots;
    if (!rootKids.empty()) {
        roots.reserve(rootKids.size());
        for (int id : rootKids) {
            if (byId.find(id) != byId.end()) roots.push_back(id);
        }
    }
    if (roots.empty()) {
        std::unordered_set<int> childIds;
        childIds.reserve(comments.size() * 2);
        for (const auto& comment : comments) {
            for (int kid : comment.kids) childIds.insert(kid);
        }
        roots.reserve(comments.size());
        for (const auto& comment : comments) {
            if (childIds.find(comment.id) == childIds.end()) roots.push_back(comment.id);
        }
        if (roots.empty()) {
            // Fully cyclic data: still show something deterministic.
            for (const auto& comment : comments) roots.push_back(comment.id);
        }
    }

    std::vector<CommentNode> result;
    result.reserve(roots.size());
    std::unordered_set<int> path;
    path.reserve(comments.size() * 2);
    for (int id : roots) {
        CommentNode node = buildNode(id, 0, maxDepth, byId, path);
        if (node.comment.id != 0) result.push_back(std::move(node));
    }
    return result;
}

int countCommentNodes(const std::vector<CommentNode>& roots) {
    int total = 0;
    for (const auto& node : roots) {
        total += 1 + countCommentNodes(node.children);
    }
    return total;
}

} // namespace hn
