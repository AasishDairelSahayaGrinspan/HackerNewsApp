#include "HNCppEngine.hpp"
#include <algorithm>
#include <cctype>
#include <regex>
#include <chrono>
#include <sstream>

namespace HackerNews {

// MARK: - Feed mapping

std::string HNCppEngine::feedEndpoint(FeedType feed) {
    switch (feed) {
        case FeedType::Top: return "topstories.json";
        case FeedType::New: return "newstories.json";
        case FeedType::Best: return "beststories.json";
        case FeedType::Ask: return "askstories.json";
        case FeedType::Show: return "showstories.json";
        case FeedType::Jobs: return "jobstories.json";
    }
    return "topstories.json";
}

std::string HNCppEngine::feedRawValue(FeedType feed) {
    switch (feed) {
        case FeedType::Top: return "Top";
        case FeedType::New: return "New";
        case FeedType::Best: return "Best";
        case FeedType::Ask: return "Ask";
        case FeedType::Show: return "Show";
        case FeedType::Jobs: return "Jobs";
    }
    return "Top";
}

FeedType HNCppEngine::feedFromString(const std::string& s) {
    std::string lower = s;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    if (lower == "top") return FeedType::Top;
    if (lower == "new") return FeedType::New;
    if (lower == "best") return FeedType::Best;
    if (lower == "ask") return FeedType::Ask;
    if (lower == "show") return FeedType::Show;
    if (lower == "jobs") return FeedType::Jobs;
    return FeedType::Top;
}

std::string HNCppEngine::feedIcon(FeedType feed) {
    switch (feed) {
        case FeedType::Top: return "flame.fill";
        case FeedType::New: return "clock.fill";
        case FeedType::Best: return "star.fill";
        case FeedType::Ask: return "questionmark.bubble.fill";
        case FeedType::Show: return "eye.fill";
        case FeedType::Jobs: return "briefcase.fill";
    }
    return "newspaper.fill";
}

std::string HNCppEngine::feedDescription(FeedType feed) {
    switch (feed) {
        case FeedType::Top: return "Most popular stories right now";
        case FeedType::New: return "Fresh submissions";
        case FeedType::Best: return "Highest voted stories";
        case FeedType::Ask: return "Ask Hacker News";
        case FeedType::Show: return "Show your work";
        case FeedType::Jobs: return "Who is hiring";
    }
    return "";
}

std::vector<FeedType> HNCppEngine::allFeeds() {
    return {FeedType::Top, FeedType::New, FeedType::Best, FeedType::Ask, FeedType::Show, FeedType::Jobs};
}

// MARK: - Deduplication & Chunking

std::vector<int> HNCppEngine::deduplicateIDs(const std::vector<int>& ids) {
    std::vector<int> out;
    out.reserve(ids.size());
    std::unordered_set<int> seen;
    seen.reserve(ids.size()*2);
    for (int id : ids) {
        if (seen.insert(id).second) out.push_back(id);
    }
    return out;
}

std::vector<std::vector<int>> HNCppEngine::chunkIDs(const std::vector<int>& ids, size_t chunkSize) {
    std::vector<std::vector<int>> chunks;
    if (ids.empty()) return chunks;
    chunks.reserve((ids.size() + chunkSize - 1) / chunkSize);
    for (size_t i = 0; i < ids.size(); i += chunkSize) {
        size_t end = std::min(i + chunkSize, ids.size());
        chunks.emplace_back(ids.begin() + i, ids.begin() + end);
    }
    return chunks;
}

// MARK: - Text processing

std::string HNCppEngine::stripHTML(const std::string& html) {
    if (html.empty()) return "";
    std::string out;
    out.reserve(html.size());
    bool inTag = false;
    for (size_t i = 0; i < html.size(); ++i) {
        char ch = html[i];
        if (ch == '<') { inTag = true; continue; }
        if (ch == '>') { inTag = false; continue; }
        if (!inTag) out.push_back(ch);
    }
    // Decode entities
    auto replace = [&](const std::string& from, const std::string& to){
        size_t pos = 0;
        while ((pos = out.find(from, pos)) != std::string::npos) {
            out.replace(pos, from.size(), to);
            pos += to.size();
        }
    };
    replace("&quot;", "\"");
    replace("&#x27;", "'");
    replace("&#x2F;", "/");
    replace("&amp;", "&");
    replace("&lt;", "<");
    replace("&gt;", ">");
    replace("<p>", "\n");
    replace("</p>", "\n");
    // Trim
    size_t start = out.find_first_not_of(" \n\r\t");
    if (start == std::string::npos) return "";
    size_t end = out.find_last_not_of(" \n\r\t");
    return out.substr(start, end - start + 1);
}

std::string HNCppEngine::htmlToPlainText(const std::string& html) {
    return stripHTML(html);
}

std::string HNCppEngine::timeAgoFromInterval(double secondsAgo) {
    if (secondsAgo < 60) return std::to_string((int)secondsAgo) + "s ago";
    if (secondsAgo < 3600) return std::to_string((int)(secondsAgo/60)) + "m ago";
    if (secondsAgo < 86400) return std::to_string((int)(secondsAgo/3600)) + "h ago";
    if (secondsAgo < 86400*30) return std::to_string((int)(secondsAgo/86400)) + "d ago";
    if (secondsAgo < 86400*365) return std::to_string((int)(secondsAgo/(86400*30))) + "mo ago";
    return std::to_string((int)(secondsAgo/(86400*365))) + "y ago";
}

std::string HNCppEngine::timeAgoFromUnix(double unixTime) {
    if (unixTime <= 0) return "unknown";
    auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    double ago = static_cast<double>(now) - unixTime;
    return timeAgoFromInterval(ago);
}

// MARK: - URL

std::string HNCppEngine::extractDomain(const std::string& url) {
    HNItem tmp; tmp.url = url;
    std::string d = tmp.domain();
    if (d.empty()) return "";
    // Reject invalid hosts: whitespace means not a URL (e.g. "not a url").
    if (d.find_first_of(" \t\n\r") != std::string::npos) return "";
    // Require dot so bare tokens without TLD are treated as invalid.
    if (d.find('.') == std::string::npos) return "";
    return d;
}

std::string HNCppEngine::storyURL(int storyID) {
    return "https://news.ycombinator.com/item?id=" + std::to_string(storyID);
}

std::string HNCppEngine::itemEndpoint(int itemID) {
    return "item/" + std::to_string(itemID) + ".json";
}

} // namespace HackerNews
