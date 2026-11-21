#pragma once

#include "Feed.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

namespace hn {

// MARK: - Errors

enum class ErrorCode : int {
    None = 0,
    Offline = 1,
    Timeout = 2,
    Http = 3,
    Decode = 4,
    NotFound = 5,
    Store = 6,
    Cancelled = 7,
    Unknown = 8
};

struct Error {
    ErrorCode code = ErrorCode::None;
    int httpStatus = 0;
    std::string message;
    bool retryable = false;

    explicit operator bool() const { return code != ErrorCode::None; }
};

const char* errorName(ErrorCode code);

// MARK: - Lifecycle

/// Mirrors the phase machine of a market-data feed handler:
/// idle -> loading/refreshing -> loaded | failed.
enum class Phase : int {
    Idle = 0,
    Loading = 1,
    Refreshing = 2,
    Loaded = 3,
    Failed = 4
};

const char* phaseName(Phase phase);

// MARK: - Wire item

/// Decoded Hacker News item. This is the only shape produced by the JSON
/// decoder; stories/comments are projections of it.
struct Item {
    int id = 0;
    std::string type;
    std::string by;
    std::string title;
    std::string url;
    std::string text;
    double time = 0;
    int score = 0;
    int descendants = 0;
    int parent = 0;
    int poll = 0;
    std::vector<int> kids;
    std::vector<int> parts;
    bool deleted = false;
    bool dead = false;
};

// MARK: - Domain rows

struct Story {
    int id = 0;
    std::string type;
    std::string title;
    std::string author;
    std::string url;
    std::string text;
    std::string domain;
    std::string timeAgo;
    double createdAt = 0;
    int score = 0;
    int commentCount = 0;
    std::vector<int> kids;
    std::vector<int> parts;
    bool dead = false;
    bool deleted = false;
    bool saved = false;
    Feed feed = Feed::Top;
    double fetchedAt = 0;
};

struct Comment {
    int id = 0;
    int storyId = 0;
    int parentId = 0;
    std::string author;
    std::string text;
    double createdAt = 0;
    bool dead = false;
    bool deleted = false;
    std::vector<int> kids;
    double fetchedAt = 0;
};

struct CommentNode {
    Comment comment;
    std::vector<CommentNode> children;
    int depth = 0;
};

struct SavedStory {
    int storyId = 0;
    double savedAt = 0;
    std::string title;
    std::string author;
    std::string url;
    std::string domain;
    int score = 0;
};

struct FeedMeta {
    Feed feed = Feed::Top;
    double fetchedAt = 0;
    std::vector<int> ids;
};

// MARK: - Snapshots (the engine's public "market data")

struct FeedSnapshot {
    Feed feed = Feed::Top;
    uint64_t revision = 0;
    Phase phase = Phase::Idle;
    std::vector<Story> stories;
    double lastSyncAt = 0;
    bool offline = false;
    bool stale = false;
    Error error;
};

struct StorySnapshot {
    int storyId = 0;
    uint64_t revision = 0;
    Phase phase = Phase::Idle;
    std::optional<Story> story;
    Error error;
};

struct CommentsSnapshot {
    int storyId = 0;
    uint64_t revision = 0;
    std::vector<CommentNode> roots;
    int totalLoaded = 0;
    bool loading = false;
    bool complete = false;
    Error error;
};

struct SavedSnapshot {
    uint64_t revision = 0;
    std::vector<SavedStory> stories;
};

// MARK: - Telemetry

struct Metrics {
    uint64_t requests = 0;
    uint64_t failures = 0;
    uint64_t retries = 0;
    uint64_t bytesReceived = 0;
    uint64_t itemsParsed = 0;
    uint64_t cacheHits = 0;
    uint64_t cacheMisses = 0;
    uint64_t snapshotsEmitted = 0;
    uint64_t commentsFetched = 0;
    uint64_t searchQueries = 0;
    int inFlight = 0;
    double lastLatencyMs = 0;
    double totalLatencyMs = 0;
    uint64_t latencySamples = 0;

    double averageLatencyMs() const {
        return latencySamples == 0 ? 0 : totalLatencyMs / static_cast<double>(latencySamples);
    }
};

struct Status {
    uint64_t revision = 0;
    Feed feed = Feed::Top;
    Phase phase = Phase::Idle;
    bool offline = false;
    double lastSyncAt = 0;
    int cachedStories = 0;
    int cachedComments = 0;
    int savedCount = 0;
    int searchDocs = 0;
    int64_t databaseBytes = 0;
    double uptimeSeconds = 0;
    std::string coreVersion;
    Metrics metrics;
};

} // namespace hn
