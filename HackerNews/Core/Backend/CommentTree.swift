import Foundation

enum CommentTree {
    static func build(comments: [Comment],
                      rootKids: [Int],
                      maxDepth: Int = 32) -> [CommentNode] {
        guard !comments.isEmpty else { return [] }

        var byID: [Int: Comment] = [:]
        byID.reserveCapacity(comments.count)
        for comment in comments { byID[comment.id] = comment }

        var roots: [Int] = rootKids.filter { byID[$0] != nil }
        if roots.isEmpty {
            let childIDs = Set(comments.flatMap(\.kids))
            roots = comments.map(\.id).filter { !childIDs.contains($0) }
        }
        if roots.isEmpty {
            roots = comments.map(\.id)
        }

        var path = Set<Int>()
        return roots.compactMap { buildNode(id: $0, depth: 0, maxDepth: maxDepth, byID: byID, path: &path) }
    }

    static func count(_ nodes: [CommentNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + count($1.children) }
    }

    private static func buildNode(id: Int,
                                  depth: Int,
                                  maxDepth: Int,
                                  byID: [Int: Comment],
                                  path: inout Set<Int>) -> CommentNode? {
        guard let comment = byID[id], !path.contains(id) else { return nil }
        if depth >= maxDepth {
            return CommentNode(comment: comment, depth: depth)
        }

        path.insert(id)
        let children = comment.kids.compactMap {
            buildNode(id: $0, depth: depth + 1, maxDepth: maxDepth, byID: byID, path: &path)
        }
        path.remove(id)

        return CommentNode(comment: comment, depth: depth, children: children)
    }
}
