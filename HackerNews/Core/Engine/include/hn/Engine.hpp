#pragma once

#include "hn/ApiClient.hpp"
#include "hn/Dispatcher.hpp"
#include "hn/SearchIndex.hpp"
#include "hn/Store.hpp"
#include "hn/Transport.hpp"
#include "hn/Types.hpp"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace hn {

/// The native Hacker News engine.
///
/// Design mirrors a trading-system core:
///   * one dispatcher thread owns all mutable state (deterministic events)
///   * network I/O is asynchronous and only posts results back
///   * snapshots carry a monotonically increasing revision
///   * SQLite is the write-behind journal, the in-memory cache is the book
///   * telemetry is exposed as a status snapshot
class Engine {
public:
    class Listener {
    public:
        virtual ~Listener() = default;
        virtual void onFeed(const FeedSnapshot& snapshot) = 0;
        virtual void onStory(const StorySnapshot& snapshot) = 0;
        virtual void onComments(const CommentsSnapshot& snapshot) = 0;
        virtual void onSaved(const SavedSnapshot& snapshot) = 0;
        virtual void onStatus(const Status& status) = 0;
    };

    Engine(std::string databasePath, std::string baseUrl, std::unique_ptr<Transport> transport);
    ~Engine();

    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;

    void setListener(Listener* listener);
    void start();
    void shutdown();

    // Commands (thread-safe, asynchronous).
    void selectFeed(Feed feed);
    void refreshFeed();
    void loadMore();
    void openStory(int storyId);
    void refreshStory(int storyId);
    void loadComments(int storyId, bool force);
    void toggleSave(int storyId);
    void setSaved(int storyId, bool saved);
    void clearCache(bool keepSaved);
    void evictCache();

    // Synchronous reads used by the bridge for search and the saved tab.
    bool isSaved(int storyId) const;
    std::vector<SavedStory> savedStories() const;
    std::vector<Story> search(const std::string& query, int limit) const;
    Status status() const;
    Metrics metrics() const;
    std::string version() const;

private:
    struct FeedState {
        Feed feed = Feed::Top;
        Phase phase = Phase::Idle;
        std::vector<Story> stories;
        Error error;
        double lastSyncAt = 0;
        int loadedCount = 0;
        bool refreshing = false;
        bool loadingMore = false;
    };

    struct StoryState {
        int id = 0;
        Phase phase = Phase::Idle;
        std::optional<Story> story;
        Error error;
    };

    struct CommentState {
        int storyId = 0;
        uint64_t generation = 0;
        bool loading = false;
        bool complete = false;
        int totalLoaded = 0;
        int maxDepth = 6;
        int hardCap = 500;
        int depth = 0;
        std::vector<int> frontier;
        std::vector<int> nextLevel;
        std::unordered_set<int> seen;
        Error error;
    };

    void initialize();
    void heartbeat();

    void loadFeedFromStore(Feed feed);
    bool needsRefresh(Feed feed) const;

    void emitFeed();
    void emitStory(int storyId);
    void emitComments(int storyId);
    void emitSaved();
    void emitStatus();

    void refreshFeedInternal(Feed feed);
    void loadMoreInternal(Feed feed);
    void fetchStoryInternal(int storyId);
    void startComments(int storyId, bool force);
    void beginCommentBFS(int storyId, uint64_t generation, const std::vector<int>& rootKids);
    void stepComments(int storyId, uint64_t generation);

    Story storyFromItem(const Item& item, Feed feed) const;
    Comment commentFromItem(const Item& item, int storyId) const;
    std::vector<CommentNode> buildTree(int storyId) const;
    CommentsSnapshot buildCommentsSnapshot(int storyId) const;

    void rebuildSearchIndex();
    void updateSavedStoryFlags();
    void setOffline(bool offline);
    void post(std::function<void()> task);
    void postDelayed(int delayMs, std::function<void()> task);

    FeedState& feedState(Feed feed);
    const FeedState& feedState(Feed feed) const;

    std::string databasePath_;
    std::string baseUrl_;
    std::unique_ptr<Transport> transport_;
    Store store_;
    SearchIndex index_;
    std::shared_ptr<Dispatcher> dispatcher_;
    Metrics metrics_;
    ApiClient api_;
    std::atomic<Listener*> listener_{nullptr};

    std::unordered_map<int, FeedState> feeds_;
    std::unordered_map<int, StoryState> stories_;
    std::unordered_map<int, CommentState> comments_;
    std::unordered_set<int> savedIds_;
    Feed currentFeed_ = Feed::Top;
    bool offline_ = false;
    bool started_ = false;
    double startedAt_ = 0;
    std::atomic<uint64_t> revision_{0};
    mutable std::atomic<uint64_t> searchQueries_{0};

    mutable std::mutex statusMutex_;
    Status status_;
};

} // namespace hn
