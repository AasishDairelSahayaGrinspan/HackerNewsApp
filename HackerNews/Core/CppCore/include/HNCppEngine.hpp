#pragma once
#include "HNTypes.hpp"
#include "CachePolicyCpp.hpp"
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>

namespace HackerNews {

class HNCppEngine {
public:
    // Feed mapping
    static std::string feedEndpoint(FeedType feed);
    static std::string feedRawValue(FeedType feed);
    static FeedType feedFromString(const std::string& s);
    static std::string feedIcon(FeedType feed);
    static std::string feedDescription(FeedType feed);
    static std::vector<FeedType> allFeeds();

    // Core algorithms - high-performance C++ implementations
    static std::vector<int> deduplicateIDs(const std::vector<int>& ids);
    static std::vector<std::vector<int>> chunkIDs(const std::vector<int>& ids, size_t chunkSize);
    
    // Merge network + cached preserving user-owned saved state
    // Feed membership is separate from story cache - saved stories never deleted
    static std::vector<HNItem> mergeStories(
        const std::vector<HNItem>& cached,
        const std::vector<HNItem>& network,
        const std::unordered_set<int>& savedIDs
    );

    // Comment tree building - optimized for 500+ nodes
    static std::vector<CommentNode> buildCommentTree(
        const std::vector<HNItem>& comments,
        const std::vector<int>& rootKids
    );
    static std::vector<CommentNode> buildCommentTreeFlat(
        const std::vector<HNItem>& comments
    );
    static void flattenTree(const std::vector<CommentNode>& nodes, std::vector<const HNItem*>& out, bool respectCollapse = true);
    static size_t countNodes(const std::vector<CommentNode>& nodes);

    // Text processing
    static std::string stripHTML(const std::string& html);
    static std::string htmlToPlainText(const std::string& html);
    static std::string timeAgoFromUnix(double unixTime);
    static std::string timeAgoFromInterval(double secondsAgo);

    // Search - local cached search (mirrors StoryRepository.search)
    static std::vector<HNItem> search(
        const std::vector<HNItem>& items,
        const std::string& query
    );

    // Cache eviction policy - mirrors PersistenceController.evictExpiredCache
    struct EvictionResult {
        std::vector<int> keepIDs;
        std::vector<int> evictIDs;
    };
    static EvictionResult evictionPlan(
        const std::vector<HNItem>& allStories,
        const std::unordered_map<int, double>& lastFetchedMap, // id -> age
        const std::unordered_set<int>& savedIDs,
        const std::unordered_set<int>& metadataIDs,
        double maxAgeSeconds,
        double cutoffAge
    );

    // URL helpers
    static std::string extractDomain(const std::string& url);
    static std::string storyURL(int storyID);
    static std::string itemEndpoint(int itemID);
};

} // namespace HackerNews
