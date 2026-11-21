#pragma once

#include "hn/Types.hpp"

#include <mutex>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

struct sqlite3;

namespace hn {

/// SQLite-backed durable store. The engine is the only writer; public methods
/// are internally serialized so synchronous bridge queries (search/saved)
/// can safely read while the dispatcher works.
class Store {
public:
    Store();
    ~Store();

    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;

    bool open(const std::string& path, std::string* error = nullptr);
    void close();
    bool isOpen() const;

    bool upsertStory(const Story& story);
    bool upsertStories(const std::vector<Story>& stories);
    std::optional<Story> story(int storyId) const;
    std::vector<Story> stories(const std::vector<int>& ids) const;
    std::vector<Story> allStories() const;

    bool setFeedMeta(const FeedMeta& meta);
    std::optional<FeedMeta> feedMeta(Feed feed) const;

    bool upsertComments(const std::vector<Comment>& comments);
    std::vector<Comment> comments(int storyId) const;

    bool setSaved(int storyId, bool saved, const Story* story);
    std::optional<SavedStory> savedStory(int storyId) const;
    std::vector<SavedStory> savedStories() const;
    std::unordered_set<int> savedIds() const;

    int countStories() const;
    int countComments() const;
    int countSaved() const;
    int64_t databaseBytes() const;

    bool evict(int maxFeedItems, double maxAgeSeconds);
    bool clear(bool keepSaved);
    bool vacuum();

    std::string lastError() const;

private:
    bool exec(const char* sql, std::string* error = nullptr) const;
    bool ensureSchema(std::string* error);
    void setError(const std::string& message) const;

    mutable std::mutex mutex_;
    sqlite3* db_ = nullptr;
    std::string path_;
    mutable std::string lastError_;
};

} // namespace hn
