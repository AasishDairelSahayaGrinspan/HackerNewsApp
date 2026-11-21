#include "hn/Engine.hpp"

#include "hn/CachePolicy.hpp"
#include "hn/Text.hpp"
#include "hn/Tree.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>

namespace hn {

namespace {

constexpr int kPageSize = 30;
constexpr int kItemConcurrency = 8;
constexpr int kCommentConcurrency = 12;
constexpr int kCommentChunkSize = 25;
constexpr int kCommentMaxDepth = 6;
constexpr int kCommentHardCap = 500;
constexpr int kCommentBranchLimit = 30;
constexpr double kEvictMaxAgeSeconds = 3 * 24 * 60 * 60;

Error genericError(const std::string& message, bool retryable = true) {
    Error error;
    error.code = ErrorCode::Unknown;
    error.message = message;
    error.retryable = retryable;
    return error;
}

} // namespace

Engine::Engine(std::string databasePath, std::string baseUrl, std::unique_ptr<Transport> transport)
    : databasePath_(std::move(databasePath)),
      baseUrl_(std::move(baseUrl)),
      transport_(std::move(transport)),
      dispatcher_(std::make_shared<Dispatcher>()),
      api_(*transport_, baseUrl_, dispatcher_, metrics_) {
    status_.coreVersion = version();
}

Engine::~Engine() {
    shutdown();
}

void Engine::setListener(Listener* listener) {
    listener_.store(listener, std::memory_order_release);
}

void Engine::start() {
    if (started_) return;
    started_ = true;
    startedAt_ = nowUnix();

    std::string error;
    if (!store_.open(databasePath_, &error)) {
        std::fprintf(stderr, "[HNEngine] store open failed (%s); falling back to memory\n", error.c_str());
        store_.open(":memory:", nullptr);
    }

    rebuildSearchIndex();
    savedIds_ = store_.savedIds();

    dispatcher_->start();
    post([this] { initialize(); });
}

void Engine::shutdown() {
    if (!started_) {
        dispatcher_->stop();
        return;
    }
    started_ = false;
    listener_.store(nullptr, std::memory_order_release);
    dispatcher_->stop();
    transport_->cancelAll();
    store_.close();
}

void Engine::post(std::function<void()> task) {
    dispatcher_->post(std::move(task));
}

void Engine::postDelayed(int delayMs, std::function<void()> task) {
    dispatcher_->postDelayed(delayMs, std::move(task));
}

Engine::FeedState& Engine::feedState(Feed feed) {
    return feeds_[static_cast<int>(feed)];
}

const Engine::FeedState& Engine::feedState(Feed feed) const {
    const auto it = feeds_.find(static_cast<int>(feed));
    if (it != feeds_.end()) return it->second;
    static const FeedState empty;
    return empty;
}

void Engine::initialize() {
    loadFeedFromStore(currentFeed_);
    emitFeed();
    emitStatus();
    if (needsRefresh(currentFeed_)) {
        refreshFeedInternal(currentFeed_);
    }
    heartbeat();
}

void Engine::heartbeat() {
    emitStatus();
    postDelayed(2000, [this] { heartbeat(); });
}

void Engine::selectFeed(Feed feed) {
    post([this, feed] {
        if (currentFeed_ == feed) {
            if (needsRefresh(feed)) {
                refreshFeedInternal(feed);
            } else {
                emitFeed();
            }
            return;
        }
        currentFeed_ = feed;
        loadFeedFromStore(feed);
        emitFeed();
        emitStatus();
        if (needsRefresh(feed)) {
            refreshFeedInternal(feed);
        }
    });
}

void Engine::refreshFeed() {
    post([this] { refreshFeedInternal(currentFeed_); });
}

void Engine::loadMore() {
    post([this] { loadMoreInternal(currentFeed_); });
}

void Engine::openStory(int storyId) {
    post([this, storyId] {
        auto& state = stories_[storyId];
        state.id = storyId;
        state.error = {};
        state.phase = Phase::Loading;

        auto cached = store_.story(storyId);
        if (cached) {
            cached->saved = savedIds_.count(storyId) > 0;
            cached->feed = currentFeed_;
            state.story = *cached;
        }
        emitStory(storyId);

        if (cached) {
            const auto freshness = CachePolicy::freshnessForAge(nowUnix() - cached->fetchedAt);
            if (freshness == CachePolicy::Freshness::Fresh) {
                state.phase = Phase::Loaded;
                emitStory(storyId);
                emitStatus();
                return;
            }
            metrics_.cacheHits++;
        } else {
            metrics_.cacheMisses++;
        }

        fetchStoryInternal(storyId);
    });
}

void Engine::refreshStory(int storyId) {
    post([this, storyId] {
        auto& state = stories_[storyId];
        state.id = storyId;
        state.phase = state.story ? Phase::Refreshing : Phase::Loading;
        state.error = {};
        emitStory(storyId);
        fetchStoryInternal(storyId);
    });
}

void Engine::fetchStoryInternal(int storyId) {
    api_.fetchItem(storyId, [this, storyId](std::optional<Item> item, Error error) {
        auto& state = stories_[storyId];
        state.id = storyId;
        if (item) {
            Story story = storyFromItem(*item, currentFeed_);
            story.saved = savedIds_.count(storyId) > 0;
            store_.upsertStory(story);
            index_.upsert(story);
            state.story = story;
            state.phase = Phase::Loaded;
            state.error = {};
            setOffline(false);
        } else {
            state.error = error;
            state.phase = state.story ? Phase::Loaded : Phase::Failed;
            if (error.code == ErrorCode::Offline) setOffline(true);
        }
        emitStory(storyId);
        emitStatus();
    });
}

void Engine::loadComments(int storyId, bool force) {
    post([this, storyId, force] { startComments(storyId, force); });
}

void Engine::startComments(int storyId, bool force) {
    auto& state = comments_[storyId];
    state.storyId = storyId;
    state.generation++;
    const uint64_t generation = state.generation;
    state.loading = true;
    state.complete = false;
    state.error = {};
    state.depth = 0;
    state.maxDepth = kCommentMaxDepth;
    state.hardCap = kCommentHardCap;
    state.frontier.clear();
    state.nextLevel.clear();
    state.seen.clear();
    state.totalLoaded = static_cast<int>(store_.comments(storyId).size());

    emitComments(storyId);

    auto cachedStory = store_.story(storyId);
    const auto cachedComments = store_.comments(storyId);

    if (!cachedComments.empty() && !force && cachedStory) {
        const auto freshness = CachePolicy::freshnessForAge(nowUnix() - cachedStory->fetchedAt);
        if (freshness == CachePolicy::Freshness::Fresh) {
            state.loading = false;
            state.complete = true;
            emitComments(storyId);
            emitStatus();
            return;
        }
        metrics_.cacheHits++;
    }

    if (cachedStory && !cachedStory->kids.empty()) {
        beginCommentBFS(storyId, generation, cachedStory->kids);
        return;
    }

    if (cachedStory && cachedStory->kids.empty()) {
        state.loading = false;
        state.complete = true;
        emitComments(storyId);
        emitStatus();
        return;
    }

    api_.fetchItem(storyId, [this, storyId, generation](std::optional<Item> item, Error error) {
        auto it = comments_.find(storyId);
        if (it == comments_.end() || it->second.generation != generation) return;
        auto& state = it->second;
        if (!item) {
            state.loading = false;
            state.error = error;
            if (error.code == ErrorCode::Offline) setOffline(true);
            emitComments(storyId);
            emitStatus();
            return;
        }

        Story story = storyFromItem(*item, currentFeed_);
        story.saved = savedIds_.count(storyId) > 0;
        store_.upsertStory(story);
        index_.upsert(story);
        beginCommentBFS(storyId, generation, story.kids);
    });
}

void Engine::beginCommentBFS(int storyId, uint64_t generation, const std::vector<int>& rootKids) {
    auto it = comments_.find(storyId);
    if (it == comments_.end() || it->second.generation != generation) return;
    auto& state = it->second;

    state.frontier.clear();
    state.nextLevel.clear();
    state.seen.clear();
    state.depth = 0;
    state.seen.reserve(rootKids.size() * 2);
    for (int id : rootKids) {
        if (id > 0 && state.seen.insert(id).second) state.frontier.push_back(id);
    }
    state.loading = true;
    state.complete = false;

    if (state.frontier.empty()) {
        state.loading = false;
        state.complete = true;
        emitComments(storyId);
        emitStatus();
        return;
    }

    emitComments(storyId);
    stepComments(storyId, generation);
}

void Engine::stepComments(int storyId, uint64_t generation) {
    auto it = comments_.find(storyId);
    if (it == comments_.end()) return;
    auto& state = it->second;
    if (state.generation != generation) return;

    if (state.frontier.empty() && !state.nextLevel.empty()) {
        state.frontier = std::move(state.nextLevel);
        state.nextLevel.clear();
        state.depth++;
    }

    const bool finished = state.frontier.empty() ||
                          state.depth >= state.maxDepth ||
                          state.totalLoaded >= state.hardCap;
    if (finished) {
        state.loading = false;
        state.complete = true;
        emitComments(storyId);
        emitStatus();
        return;
    }

    int available = state.hardCap - state.totalLoaded;
    if (available <= 0) {
        state.loading = false;
        state.complete = true;
        emitComments(storyId);
        emitStatus();
        return;
    }

    const int take = std::min({static_cast<int>(state.frontier.size()), kCommentChunkSize, available});
    std::vector<int> chunk(state.frontier.begin(), state.frontier.begin() + take);
    state.frontier.erase(state.frontier.begin(), state.frontier.begin() + take);
    if (chunk.empty()) {
        state.loading = false;
        state.complete = true;
        emitComments(storyId);
        emitStatus();
        return;
    }

    api_.fetchItems(chunk, kCommentConcurrency, [this, storyId, generation](std::vector<Item> items) {
        auto it = comments_.find(storyId);
        if (it == comments_.end() || it->second.generation != generation) return;
        auto& state = it->second;

        std::vector<Comment> comments;
        comments.reserve(items.size());
        for (const auto& item : items) {
            comments.push_back(commentFromItem(item, storyId));
            if (state.depth + 1 < state.maxDepth) {
                int branch = 0;
                for (int kid : item.kids) {
                    if (++branch > kCommentBranchLimit) break;
                    if (kid <= 0) continue;
                    if (state.seen.insert(kid).second) {
                        state.nextLevel.push_back(kid);
                    }
                }
            }
        }

        if (!comments.empty()) {
            store_.upsertComments(comments);
            metrics_.commentsFetched += comments.size();
        }

        state.totalLoaded = static_cast<int>(store_.comments(storyId).size());

        if (state.frontier.empty()) {
            state.frontier = std::move(state.nextLevel);
            state.nextLevel.clear();
            state.depth++;
        }

        const bool done = state.frontier.empty() ||
                          state.depth >= state.maxDepth ||
                          state.totalLoaded >= state.hardCap;
        if (done) {
            state.loading = false;
            state.complete = true;
        }

        emitComments(storyId);
        emitStatus();

        if (!done) {
            post([this, storyId, generation] { stepComments(storyId, generation); });
        }
    });
}

void Engine::toggleSave(int storyId) {
    post([this, storyId] {
        const bool currentlySaved = savedIds_.count(storyId) > 0;
        const bool nextSaved = !currentlySaved;
        auto story = store_.story(storyId);
        store_.setSaved(storyId, nextSaved, story ? &*story : nullptr);
        if (nextSaved) {
            savedIds_.insert(storyId);
        } else {
            savedIds_.erase(storyId);
        }
        updateSavedStoryFlags();
        emitSaved();
        emitFeed();
        if (stories_.count(storyId)) emitStory(storyId);
        emitStatus();
    });
}

void Engine::setSaved(int storyId, bool saved) {
    post([this, storyId, saved] {
        const bool currentlySaved = savedIds_.count(storyId) > 0;
        if (currentlySaved == saved) {
            emitSaved();
            return;
        }
        auto story = store_.story(storyId);
        store_.setSaved(storyId, saved, story ? &*story : nullptr);
        if (saved) {
            savedIds_.insert(storyId);
        } else {
            savedIds_.erase(storyId);
        }
        updateSavedStoryFlags();
        emitSaved();
        emitFeed();
        if (stories_.count(storyId)) emitStory(storyId);
        emitStatus();
    });
}

bool Engine::isSaved(int storyId) const {
    return store_.savedStory(storyId).has_value();
}

std::vector<SavedStory> Engine::savedStories() const {
    return store_.savedStories();
}

std::vector<Story> Engine::search(const std::string& query, int limit) const {
    searchQueries_.fetch_add(1, std::memory_order_relaxed);
    const auto ids = index_.search(query, limit);
    auto stories = store_.stories(ids);
    const auto saved = store_.savedIds();
    for (auto& story : stories) {
        story.saved = saved.count(story.id) > 0;
    }
    return stories;
}

void Engine::clearCache(bool keepSaved) {
    post([this, keepSaved] {
        store_.clear(keepSaved);
        savedIds_ = keepSaved ? store_.savedIds() : std::unordered_set<int>{};
        rebuildSearchIndex();
        loadFeedFromStore(currentFeed_);
        emitFeed();
        emitSaved();
        emitStatus();
        if (needsRefresh(currentFeed_)) {
            refreshFeedInternal(currentFeed_);
        }
    });
}

void Engine::evictCache() {
    post([this] {
        store_.evict(200, kEvictMaxAgeSeconds);
        rebuildSearchIndex();
        loadFeedFromStore(currentFeed_);
        emitFeed();
        emitStatus();
    });
}

void Engine::refreshFeedInternal(Feed feed) {
    auto& state = feedState(feed);
    if (state.refreshing) return;
    state.refreshing = true;
    state.error = {};
    state.phase = state.stories.empty() ? Phase::Loading : Phase::Refreshing;
    emitFeed();
    emitStatus();

    api_.fetchFeedIDs(feed, [this, feed](std::optional<std::vector<int>> ids, Error error) {
        auto& state = feedState(feed);
        if (!ids) {
            state.refreshing = false;
            state.error = error;
            state.phase = Phase::Failed;
            if (error.code == ErrorCode::Offline) setOffline(true);
            emitFeed();
            emitStatus();
            return;
        }

        const std::vector<int> allIds = *ids;
        const int firstCount = std::min<int>(kPageSize, static_cast<int>(allIds.size()));
        std::vector<int> first(allIds.begin(), allIds.begin() + firstCount);

        api_.fetchItems(first, kItemConcurrency, [this, feed, allIds, firstCount](std::vector<Item> items) {
            auto& state = feedState(feed);
            if (items.empty() && !allIds.empty()) {
                state.refreshing = false;
                state.error = genericError("Couldn't load stories. Pull to refresh.");
                state.phase = Phase::Failed;
                emitFeed();
                emitStatus();
                return;
            }

            std::vector<Story> stories;
            stories.reserve(items.size());
            for (const auto& item : items) {
                stories.push_back(storyFromItem(item, feed));
            }
            if (!stories.empty()) {
                store_.upsertStories(stories);
                for (const auto& story : stories) index_.upsert(story);
            }

            FeedMeta meta;
            meta.feed = feed;
            meta.fetchedAt = nowUnix();
            meta.ids = allIds;
            store_.setFeedMeta(meta);

            state.lastSyncAt = meta.fetchedAt;
            state.loadedCount = firstCount;

            auto loaded = store_.stories(allIds);
            for (auto& story : loaded) {
                story.feed = feed;
                story.saved = savedIds_.count(story.id) > 0;
            }
            state.stories = std::move(loaded);
            state.refreshing = false;
            state.error = {};
            state.phase = state.stories.empty() ? Phase::Failed : Phase::Loaded;
            if (state.stories.empty()) {
                state.error = genericError("No stories available.");
            }
            setOffline(false);
            emitFeed();
            emitStatus();
        });
    });
}

void Engine::loadMoreInternal(Feed feed) {
    auto& state = feedState(feed);
    if (state.loadingMore || state.refreshing) return;

    auto meta = store_.feedMeta(feed);
    if (!meta) return;
    const int start = std::max(0, state.loadedCount);
    if (start >= static_cast<int>(meta->ids.size())) return;

    const int end = std::min<int>(start + kPageSize, static_cast<int>(meta->ids.size()));
    std::vector<int> next(meta->ids.begin() + start, meta->ids.begin() + end);
    if (next.empty()) return;

    state.loadingMore = true;
    const int requested = static_cast<int>(next.size());
    const std::vector<int> allIds = meta->ids;

    api_.fetchItems(next, kItemConcurrency, [this, feed, allIds, requested](std::vector<Item> items) {
        auto& state = feedState(feed);
        if (!items.empty()) {
            std::vector<Story> stories;
            stories.reserve(items.size());
            for (const auto& item : items) stories.push_back(storyFromItem(item, feed));
            store_.upsertStories(stories);
            for (const auto& story : stories) index_.upsert(story);
        }

        state.loadedCount += requested;
        auto loaded = store_.stories(allIds);
        for (auto& story : loaded) {
            story.feed = feed;
            story.saved = savedIds_.count(story.id) > 0;
        }
        state.stories = std::move(loaded);
        state.loadingMore = false;
        emitFeed();
        emitStatus();
    });
}

void Engine::loadFeedFromStore(Feed feed) {
    auto& state = feedState(feed);
    state.feed = feed;
    state.error = {};

    auto meta = store_.feedMeta(feed);
    if (!meta) {
        state.stories.clear();
        state.lastSyncAt = 0;
        state.loadedCount = 0;
        state.phase = Phase::Idle;
        return;
    }

    auto loaded = store_.stories(meta->ids);
    for (auto& story : loaded) {
        story.feed = feed;
        story.saved = savedIds_.count(story.id) > 0;
    }
    state.stories = std::move(loaded);
    state.lastSyncAt = meta->fetchedAt;
    state.loadedCount = static_cast<int>(state.stories.size());
    state.phase = state.stories.empty() ? Phase::Idle : Phase::Loaded;
}

bool Engine::needsRefresh(Feed feed) const {
    const auto& state = feedState(feed);
    if (state.stories.empty()) return true;
    if (state.lastSyncAt <= 0) return true;
    return CachePolicy::freshnessForFetchedAt(state.lastSyncAt, nowUnix()) != CachePolicy::Freshness::Fresh;
}

Story Engine::storyFromItem(const Item& item, Feed feed) const {
    Story story;
    story.id = item.id;
    story.type = item.type;
    story.title = item.title;
    story.author = item.by;
    story.url = item.url;
    story.text = item.text;
    story.createdAt = item.time;
    story.score = item.score;
    story.commentCount = item.descendants > 0 ? item.descendants : static_cast<int>(item.kids.size());
    story.kids = item.kids;
    story.parts = item.parts;
    story.dead = item.dead;
    story.deleted = item.deleted;
    story.feed = feed;
    story.fetchedAt = nowUnix();
    story.domain = domainFromURL(story.url);
    story.timeAgo = timeAgoFromUnix(story.createdAt);
    return story;
}

Comment Engine::commentFromItem(const Item& item, int storyId) const {
    Comment comment;
    comment.id = item.id;
    comment.storyId = storyId;
    comment.parentId = item.parent;
    comment.author = item.by;
    comment.text = item.text;
    comment.createdAt = item.time;
    comment.dead = item.dead;
    comment.deleted = item.deleted;
    comment.kids = item.kids;
    comment.fetchedAt = nowUnix();
    return comment;
}

std::vector<CommentNode> Engine::buildTree(int storyId) const {
    const auto comments = store_.comments(storyId);
    const auto story = store_.story(storyId);
    const std::vector<int> roots = story ? story->kids : std::vector<int>{};
    return buildCommentTree(comments, roots, 32);
}

CommentsSnapshot Engine::buildCommentsSnapshot(int storyId) const {
    CommentsSnapshot snapshot;
    snapshot.storyId = storyId;
    snapshot.roots = buildTree(storyId);
    snapshot.totalLoaded = countCommentNodes(snapshot.roots);
    const auto it = comments_.find(storyId);
    if (it != comments_.end()) {
        snapshot.loading = it->second.loading;
        snapshot.complete = it->second.complete;
        snapshot.error = it->second.error;
    }
    return snapshot;
}

void Engine::emitFeed() {
    const auto& state = feedState(currentFeed_);
    FeedSnapshot snapshot;
    snapshot.feed = currentFeed_;
    snapshot.revision = ++revision_;
    snapshot.phase = state.phase;
    snapshot.stories = state.stories;
    snapshot.lastSyncAt = state.lastSyncAt;
    snapshot.offline = offline_;
    snapshot.stale = state.lastSyncAt > 0 &&
                     CachePolicy::freshnessForFetchedAt(state.lastSyncAt, nowUnix()) !=
                         CachePolicy::Freshness::Fresh;
    snapshot.error = state.error;
    metrics_.snapshotsEmitted++;
    if (auto* listener = listener_.load(std::memory_order_acquire)) {
        listener->onFeed(snapshot);
    }
}

void Engine::emitStory(int storyId) {
    StorySnapshot snapshot;
    snapshot.storyId = storyId;
    snapshot.revision = ++revision_;
    const auto it = stories_.find(storyId);
    if (it != stories_.end()) {
        snapshot.phase = it->second.phase;
        snapshot.story = it->second.story;
        snapshot.error = it->second.error;
    }
    metrics_.snapshotsEmitted++;
    if (auto* listener = listener_.load(std::memory_order_acquire)) {
        listener->onStory(snapshot);
    }
}

void Engine::emitComments(int storyId) {
    CommentsSnapshot snapshot = buildCommentsSnapshot(storyId);
    snapshot.revision = ++revision_;
    metrics_.snapshotsEmitted++;
    if (auto* listener = listener_.load(std::memory_order_acquire)) {
        listener->onComments(snapshot);
    }
}

void Engine::emitSaved() {
    SavedSnapshot snapshot;
    snapshot.revision = ++revision_;
    snapshot.stories = store_.savedStories();
    metrics_.snapshotsEmitted++;
    if (auto* listener = listener_.load(std::memory_order_acquire)) {
        listener->onSaved(snapshot);
    }
}

void Engine::emitStatus() {
    Status status;
    status.revision = revision_.load(std::memory_order_relaxed);
    status.feed = currentFeed_;
    status.phase = feedState(currentFeed_).phase;
    status.offline = offline_;
    status.lastSyncAt = feedState(currentFeed_).lastSyncAt;
    status.cachedStories = store_.countStories();
    status.cachedComments = store_.countComments();
    status.savedCount = store_.countSaved();
    status.searchDocs = index_.size();
    status.databaseBytes = store_.databaseBytes();
    status.uptimeSeconds = startedAt_ > 0 ? nowUnix() - startedAt_ : 0;
    status.coreVersion = version();
    status.metrics = metrics_;
    status.metrics.inFlight = api_.inFlight();
    status.metrics.searchQueries = searchQueries_.load(std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(statusMutex_);
        status_ = status;
    }
    if (auto* listener = listener_.load(std::memory_order_acquire)) {
        listener->onStatus(status);
    }
}

void Engine::rebuildSearchIndex() {
    index_.clear();
    const auto stories = store_.allStories();
    for (const auto& story : stories) index_.upsert(story);
}

void Engine::updateSavedStoryFlags() {
    for (auto& entry : feeds_) {
        for (auto& story : entry.second.stories) {
            story.saved = savedIds_.count(story.id) > 0;
        }
    }
    for (auto& entry : stories_) {
        if (entry.second.story) {
            entry.second.story->saved = savedIds_.count(entry.first) > 0;
        }
    }
}

void Engine::setOffline(bool offline) {
    offline_ = offline;
}

Status Engine::status() const {
    std::lock_guard<std::mutex> lock(statusMutex_);
    return status_;
}

Metrics Engine::metrics() const {
    return status().metrics;
}

std::string Engine::version() const {
    return "HNCore 2.0 · C++20 event-loop · SQLite write-behind";
}

} // namespace hn
