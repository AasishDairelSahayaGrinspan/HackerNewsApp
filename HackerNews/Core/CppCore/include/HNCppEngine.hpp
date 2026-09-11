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

    // Text processing
    static std::string stripHTML(const std::string& html);
    static std::string htmlToPlainText(const std::string& html);
    static std::string timeAgoFromUnix(double unixTime);
    static std::string timeAgoFromInterval(double secondsAgo);

    // URL helpers
    static std::string extractDomain(const std::string& url);
    static std::string storyURL(int storyID);
    static std::string itemEndpoint(int itemID);
};

} // namespace HackerNews
