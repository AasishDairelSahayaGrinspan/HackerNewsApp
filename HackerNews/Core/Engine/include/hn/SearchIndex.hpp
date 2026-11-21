#pragma once

#include "hn/Types.hpp"

#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace hn {

/// In-memory inverted index over cached stories. This is the engine's
/// "symbol master": search stays local, deterministic and network-free.
class SearchIndex {
public:
    void upsert(const Story& story);
    void remove(int storyId);
    void clear();
    int size() const;

    /// Returns story IDs ordered by relevance. Title matches outrank author,
    /// domain and body matches. Falls back to substring matching so partial
    /// words still behave the way users expect.
    std::vector<int> search(const std::string& query, int limit = 100) const;

private:
    struct Doc {
        int id = 0;
        std::string title;
        std::string author;
        std::string domain;
        std::string text;
        int score = 0;
        double createdAt = 0;
        std::vector<std::string> tokens;
    };

    static std::vector<std::string> tokenize(const std::string& value);
    static void addToken(std::vector<std::string>& tokens,
                         std::unordered_map<std::string, std::unordered_set<int>>& postings,
                         int storyId,
                         const std::string& token);

    mutable std::mutex mutex_;
    std::unordered_map<int, Doc> docs_;
    std::unordered_map<std::string, std::unordered_set<int>> postings_;
};

} // namespace hn
