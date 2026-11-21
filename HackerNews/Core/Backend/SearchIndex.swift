import Foundation

/// Local inverted index over cached stories. Search is intentionally
/// network-free because the official HN API has no full-text search.
@MainActor
final class SearchIndex {
    private struct Doc {
        let id: Int
        let title: String
        let author: String
        let domain: String
        let text: String
        let score: Int
        let createdAt: TimeInterval
        var tokens: [String]
    }

    private var docs: [Int: Doc] = [:]
    private var postings: [String: Set<Int>] = [:]

    var count: Int { docs.count }

    func upsert(_ story: Story) {
        remove(story.id)

        var doc = Doc(id: story.id,
                      title: story.title?.lowercased() ?? "",
                      author: story.author?.lowercased() ?? "",
                      domain: story.domain?.lowercased() ?? "",
                      text: story.text?.lowercased() ?? "",
                      score: story.score,
                      createdAt: story.createdAt?.timeIntervalSince1970 ?? 0,
                      tokens: [])

        var tokens = Set<String>()
        for field in [doc.title, doc.author, doc.domain, doc.text] {
            for token in Self.tokenize(field) { tokens.insert(token) }
        }
        doc.tokens = Array(tokens)

        for token in doc.tokens {
            postings[token, default: []].insert(doc.id)
        }
        docs[doc.id] = doc
    }

    func remove(_ storyID: Int) {
        guard let existing = docs.removeValue(forKey: storyID) else { return }
        for token in existing.tokens {
            guard var ids = postings[token] else { continue }
            ids.remove(storyID)
            if ids.isEmpty {
                postings.removeValue(forKey: token)
            } else {
                postings[token] = ids
            }
        }
    }

    func clear() {
        docs.removeAll()
        postings.removeAll()
    }

    func search(_ query: String, limit: Int = 100) -> [Int] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !docs.isEmpty else { return [] }

        let queryTokens = Self.tokenize(trimmed)
        var scores: [Int: Int] = [:]

        if !queryTokens.isEmpty {
            var candidates: Set<Int>?
            for token in queryTokens {
                var matches = Set<Int>()
                for (key, ids) in postings where key.hasPrefix(token) {
                    matches.formUnion(ids)
                }
                if let existing = candidates {
                    candidates = existing.intersection(matches)
                } else {
                    candidates = matches
                }
                if candidates?.isEmpty == true { break }
            }
            for id in candidates ?? [] { scores[id, default: 0] += 10 }
        }

        for (id, doc) in docs {
            var score = 0
            score += Self.fieldWeight(doc.title, query: trimmed) * 5
            score += Self.fieldWeight(doc.author, query: trimmed) * 3
            score += Self.fieldWeight(doc.domain, query: trimmed) * 2
            if !doc.text.isEmpty, doc.text.contains(trimmed) { score += 1 }
            if score > 0 { scores[id, default: 0] += score }
        }

        let ranked = scores.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            guard let left = docs[lhs.key], let right = docs[rhs.key] else { return lhs.key > rhs.key }
            if left.score != right.score { return left.score > right.score }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.id > right.id
        }

        return Array(ranked.prefix(max(1, limit)).map(\.key))
    }

    // MARK: - Helpers

    private static func fieldWeight(_ field: String, query: String) -> Int {
        guard !field.isEmpty else { return 0 }
        if field == query { return 8 }
        if field.hasPrefix(query) { return 5 }
        if field.contains(query) { return 3 }
        return 0
    }

    private static func tokenize(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in value.lowercased() {
            if character.isLetter || character.isNumber || character == "_" || character == "'" {
                current.append(character)
            } else if !current.isEmpty {
                if current.count >= 2 { tokens.append(current) }
                current = ""
            }
        }
        if current.count >= 2 { tokens.append(current) }
        return tokens
    }
}
