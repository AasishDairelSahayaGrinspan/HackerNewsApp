import Foundation
import SwiftData
import os

struct CommentNode: Identifiable, Equatable {
    let comment: CachedComment
    var children: [CommentNode]
    var depth: Int
    var isCollapsed: Bool = false
    var id: Int { comment.id }

    static func == (lhs: CommentNode, rhs: CommentNode) -> Bool {
        lhs.id == rhs.id && lhs.isCollapsed == rhs.isCollapsed && lhs.children == rhs.children
    }
}

@MainActor
final class CommentRepository {
    private let api: any HackerNewsAPIProtocol
    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "com.hacknews.app", category: "cache")

    init(api: any HackerNewsAPIProtocol = HackerNewsAPI(), persistence: PersistenceController) {
        self.api = api
        self.persistence = persistence
    }

    convenience init(api: any HackerNewsAPIProtocol = HackerNewsAPI()) {
        self.init(api: api, persistence: PersistenceController.shared)
    }

    func loadComments(for story: CachedStory, forceRefresh: Bool = false) async -> [CommentNode] {
        let cached = persistence.fetchComments(for: story.id)
        if !cached.isEmpty && !forceRefresh {
            let tree = buildTree(comments: cached, rootKids: nil)
            if Date().timeIntervalSince(story.lastFetchedAt) > CachePolicy.freshInterval {
                Task { await self.refreshComments(storyID: story.id, expectedKids: nil) }
            }
            return tree
        }
        do {
            let dto = try await api.fetchItem(id: story.id)
            let kids = dto.kids ?? []
            if kids.isEmpty { return [] }
            let fetched = await fetchCommentsRecursively(ids: kids, storyID: story.id, depth: 0, maxDepth: 6)
            for c in fetched {
                if let existing = fetchComment(id: c.id) {
                    existing.author = c.author
                    existing.text = c.text
                    existing.kids = c.kids
                    existing.isHnDeleted = c.isHnDeleted
                    existing.isDead = c.isDead
                    existing.lastFetchedAt = Date()
                } else {
                    persistence.context.insert(c)
                }
            }
            persistence.save()
            let all = persistence.fetchComments(for: story.id)
            return buildTree(comments: all, rootKids: kids)
        } catch {
            logger.error("Comment load failed: \(error.localizedDescription, privacy: .public)")
            if !cached.isEmpty { return buildTree(comments: cached, rootKids: nil) }
            return []
        }
    }

    func refreshComments(storyID: Int, expectedKids: [Int]?) async {
        do {
            let dto = try await api.fetchItem(id: storyID)
            let kids = expectedKids ?? dto.kids ?? []
            let fetched = await fetchCommentsRecursively(ids: kids, storyID: storyID, depth: 0, maxDepth: 6)
            for c in fetched {
                if let existing = fetchComment(id: c.id) {
                    existing.author = c.author
                    existing.text = c.text
                    existing.kids = c.kids
                    existing.isHnDeleted = c.isHnDeleted
                    existing.isDead = c.isDead
                    existing.lastFetchedAt = Date()
                } else {
                    persistence.context.insert(c)
                }
            }
            persistence.save()
        } catch {
            logger.warning("Refresh comments failed \(storyID): \(error.localizedDescription, privacy: .public)")
        }
    }

    // BFS optimized for high-volume: fetch level-by-level with C++ chunking, avoids deep recursion deadlock
    private func fetchCommentsRecursively(ids: [Int], storyID: Int, depth: Int, maxDepth: Int) async -> [CachedComment] {
        guard depth < maxDepth, !ids.isEmpty else { return [] }
        var result: [CachedComment] = []
        let hardCap = 500
        var currentLevelIDs = ids
        var currentDepth = depth

        while !currentLevelIDs.isEmpty && currentDepth < maxDepth && result.count < hardCap {
            // Chunk current level to respect concurrency and avoid 500-task spawn
            let chunks = CppEngine.chunk(currentLevelIDs, size: 25)
            var nextLevelIDs: [Int] = []
            for chunk in chunks {
                guard result.count < hardCap else { break }
                do {
                    let dtos = try await api.fetchItems(ids: chunk, maxConcurrency: 12)
                    for dto in dtos {
                        guard result.count < hardCap else { break }
                        let comment = CachedComment(from: dto, storyID: storyID)
                        result.append(comment)
                        if let kids = dto.kids, !kids.isEmpty, currentDepth + 1 < maxDepth {
                            // Limit per-node branching to 30 to prevent 1313-descendant explosion
                            let limited = kids.count > 30 ? Array(kids.prefix(30)) : kids
                            nextLevelIDs.append(contentsOf: limited)
                        }
                    }
                } catch {
                    logger.warning("Level \(currentDepth) fetch failed: \(error.localizedDescription, privacy: .public)")
                }
                // Deduplicate next level early to avoid refetching same IDs
                nextLevelIDs = CppEngine.deduplicate(nextLevelIDs)
                // Hard cap next level as well
                if nextLevelIDs.count > hardCap - result.count {
                    nextLevelIDs = Array(nextLevelIDs.prefix(hardCap - result.count))
                }
            }
            currentLevelIDs = nextLevelIDs
            currentDepth += 1
        }
        return result
    }

    // Streaming version for progressive UI (first 30 in <1s, rest in background)
    func loadCommentsStreaming(for story: CachedStory, onUpdate: @MainActor @escaping ([CommentNode]) -> Void) async {
        do {
            let dto = try await api.fetchItem(id: story.id)
            let kids = dto.kids ?? []
            guard !kids.isEmpty else { return }
            // Phase 1: first 30 top-level for instant UI
            let firstBatch = Array(kids.prefix(30))
            let fetched = await fetchCommentsRecursively(ids: firstBatch, storyID: story.id, depth: 0, maxDepth: 3)
            // Persist and publish first batch
            for c in fetched { if fetchComment(id: c.id) == nil { persistence.context.insert(c) } }
            persistence.save()
            let tree1 = buildTree(comments: persistence.fetchComments(for: story.id), rootKids: kids)
            onUpdate(tree1)

            // Phase 2: remaining top-level + deeper levels (background)
            if kids.count > 30 {
                let remaining = Array(kids.dropFirst(30))
                if !remaining.isEmpty {
                    let more = await fetchCommentsRecursively(ids: remaining, storyID: story.id, depth: 0, maxDepth: 6)
                    for c in more { if fetchComment(id: c.id) == nil { persistence.context.insert(c) } }
                    persistence.save()
                    let tree2 = buildTree(comments: persistence.fetchComments(for: story.id), rootKids: kids)
                    onUpdate(tree2)
                }
                // Depth 3->6 expansion for first batch (load replies deeper)
                let deep = await fetchCommentsRecursively(ids: firstBatch, storyID: story.id, depth: 3, maxDepth: 6)
                for c in deep { if fetchComment(id: c.id) == nil { persistence.context.insert(c) } }
                persistence.save()
                let tree3 = buildTree(comments: persistence.fetchComments(for: story.id), rootKids: kids)
                onUpdate(tree3)
            }
        } catch {
            logger.error("Streaming load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchComment(id: Int) -> CachedComment? {
        let descriptor = FetchDescriptor<CachedComment>(predicate: #Predicate { $0.id == id })
        return try? persistence.context.fetch(descriptor).first
    }

    func buildTree(comments: [CachedComment], rootKids: [Int]?) -> [CommentNode] {
        var map: [Int: CachedComment] = [:]
        for c in comments { map[c.id] = c }
        let rootIDs: [Int]
        if let rootKids { rootIDs = rootKids }
        else {
            let allKids = Set(comments.flatMap(\.kids))
            rootIDs = comments.filter { !allKids.contains($0.id) }.map(\.id)
        }
        func buildNode(id: Int, depth: Int) -> CommentNode? {
            guard let comment = map[id] else { return nil }
            let children = comment.kids.compactMap { buildNode(id: $0, depth: depth + 1) }
            return CommentNode(comment: comment, children: children, depth: depth)
        }
        return rootIDs.compactMap { buildNode(id: $0, depth: 0) }
    }
}
