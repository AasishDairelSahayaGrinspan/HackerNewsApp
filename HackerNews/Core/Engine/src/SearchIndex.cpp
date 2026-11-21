#include "hn/SearchIndex.hpp"

#include "hn/Text.hpp"

#include <algorithm>
#include <cctype>
#include <unordered_map>
#include <unordered_set>

namespace hn {

namespace {

bool isTokenChar(unsigned char c) {
    return std::isalnum(c) != 0 || c == '_' || c == '\'';
}

int fieldWeight(const std::string& field, const std::string& lowerQuery) {
    if (field.empty()) return 0;
    if (field == lowerQuery) return 8;
    if (field.rfind(lowerQuery, 0) == 0) return 5;
    if (field.find(lowerQuery) != std::string::npos) return 3;
    return 0;
}

} // namespace

std::vector<std::string> SearchIndex::tokenize(const std::string& value) {
    std::vector<std::string> tokens;
    std::string current;
    current.reserve(32);
    for (unsigned char c : value) {
        if (isTokenChar(c)) {
            current.push_back(static_cast<char>(std::tolower(c)));
        } else if (!current.empty()) {
            if (current.size() >= 2) tokens.push_back(current);
            current.clear();
        }
    }
    if (current.size() >= 2) tokens.push_back(current);
    return tokens;
}

void SearchIndex::addToken(std::vector<std::string>& tokens,
                           std::unordered_map<std::string, std::unordered_set<int>>& postings,
                           int storyId,
                           const std::string& token) {
    if (token.size() < 2) return;
    tokens.push_back(token);
    postings[token].insert(storyId);
}

void SearchIndex::upsert(const Story& story) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto existing = docs_.find(story.id);
    if (existing != docs_.end()) {
        for (const auto& token : existing->second.tokens) {
            auto posting = postings_.find(token);
            if (posting != postings_.end()) {
                posting->second.erase(story.id);
                if (posting->second.empty()) postings_.erase(posting);
            }
        }
        docs_.erase(existing);
    }

    Doc doc;
    doc.id = story.id;
    doc.title = toLowerAscii(story.title);
    doc.author = toLowerAscii(story.author);
    doc.domain = toLowerAscii(story.domain);
    doc.text = toLowerAscii(story.text);
    doc.score = story.score;
    doc.createdAt = story.createdAt;

    for (const auto& token : tokenize(doc.title)) addToken(doc.tokens, postings_, doc.id, token);
    for (const auto& token : tokenize(doc.author)) addToken(doc.tokens, postings_, doc.id, token);
    for (const auto& token : tokenize(doc.domain)) addToken(doc.tokens, postings_, doc.id, token);
    for (const auto& token : tokenize(doc.text)) addToken(doc.tokens, postings_, doc.id, token);

    docs_.emplace(doc.id, std::move(doc));
}

void SearchIndex::remove(int storyId) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = docs_.find(storyId);
    if (it == docs_.end()) return;
    for (const auto& token : it->second.tokens) {
        auto posting = postings_.find(token);
        if (posting != postings_.end()) {
            posting->second.erase(storyId);
            if (posting->second.empty()) postings_.erase(posting);
        }
    }
    docs_.erase(it);
}

void SearchIndex::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    docs_.clear();
    postings_.clear();
}

int SearchIndex::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return static_cast<int>(docs_.size());
}

std::vector<int> SearchIndex::search(const std::string& query, int limit) const {
    const std::string lowerQuery = toLowerAscii(trim(query));
    if (lowerQuery.empty()) return {};

    std::lock_guard<std::mutex> lock(mutex_);
    if (docs_.empty()) return {};

    const std::vector<std::string> queryTokens = tokenize(lowerQuery);
    std::unordered_map<int, int> scores;
    scores.reserve(docs_.size());

    if (!queryTokens.empty()) {
        // Intersect postings for multi-token queries, but keep a partial
        // score for single-token / prefix queries.
        std::unordered_set<int> candidates;
        bool first = true;
        for (const auto& token : queryTokens) {
            std::unordered_set<int> matches;
            for (const auto& entry : postings_) {
                if (entry.first.rfind(token, 0) == 0) {
                    matches.insert(entry.second.begin(), entry.second.end());
                }
            }
            if (first) {
                candidates = std::move(matches);
                first = false;
            } else {
                std::unordered_set<int> intersection;
                for (int id : candidates) {
                    if (matches.count(id)) intersection.insert(id);
                }
                candidates = std::move(intersection);
            }
            if (candidates.empty()) break;
        }
        for (int id : candidates) scores[id] += 10;
    }

    // Substring fallback / enrichment: keeps behavior close to the old
    // local contains() search while the inverted index handles common cases.
    for (const auto& entry : docs_) {
        const Doc& doc = entry.second;
        int score = 0;
        score += fieldWeight(doc.title, lowerQuery) * 5;
        score += fieldWeight(doc.author, lowerQuery) * 3;
        score += fieldWeight(doc.domain, lowerQuery) * 2;
        if (!doc.text.empty() && doc.text.find(lowerQuery) != std::string::npos) score += 1;
        if (score > 0) scores[doc.id] += score;
    }

    std::vector<std::pair<int, int>> ranked;
    ranked.reserve(scores.size());
    for (const auto& entry : scores) ranked.emplace_back(entry.first, entry.second);

    std::sort(ranked.begin(), ranked.end(), [&](const auto& a, const auto& b) {
        if (a.second != b.second) return a.second > b.second;
        const auto& da = docs_.at(a.first);
        const auto& db = docs_.at(b.first);
        if (da.score != db.score) return da.score > db.score;
        if (da.createdAt != db.createdAt) return da.createdAt > db.createdAt;
        return da.id > db.id;
    });

    std::vector<int> result;
    const int capped = std::max(1, limit);
    result.reserve(std::min<int>(static_cast<int>(ranked.size()), capped));
    for (const auto& entry : ranked) {
        result.push_back(entry.first);
        if (static_cast<int>(result.size()) >= capped) break;
    }
    return result;
}

} // namespace hn
