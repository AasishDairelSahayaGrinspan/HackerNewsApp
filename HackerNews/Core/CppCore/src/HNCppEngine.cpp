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

// MARK: - Merge (offline-first)

std::vector<HNItem> HNCppEngine::mergeStories(
    const std::vector<HNItem>& cached,
    const std::vector<HNItem>& network,
    const std::unordered_set<int>& savedIDs
) {
    // Saved IDs are never evicted - merge preserves them
    std::unordered_map<int, HNItem> map;
    map.reserve(cached.size() + network.size());
    for (const auto& c : cached) map[c.id] = c;
    for (const auto& n : network) map[n.id] = n; // network wins for fresh data
    // Ensure saved items are kept even if not in network
    // (already in cached map, so kept)
    std::vector<HNItem> result;
    result.reserve(map.size());
    for (auto& kv : map) result.push_back(kv.second);
    // Sort by id desc for determinism (real app sorts by feed order via metadata)
    std::sort(result.begin(), result.end(), [](const HNItem& a, const HNItem& b){ return a.id > b.id; });
    return result;
}

// MARK: - Comment tree

std::vector<CommentNode> HNCppEngine::buildCommentTree(
    const std::vector<HNItem>& comments,
    const std::vector<int>& rootKids
) {
    if (comments.empty() || rootKids.empty()) return {};
    std::unordered_map<int, HNItem> map;
    map.reserve(comments.size()*2);
    for (auto& c : comments) map[c.id] = c;

    std::function<CommentNode(int,int)> build = [&](int id, int depth) -> CommentNode {
        auto it = map.find(id);
        if (it == map.end()) return CommentNode{};
        CommentNode node;
        node.comment = it->second;
        node.depth = depth;
        for (int kid : it->second.kids) {
            auto cit = map.find(kid);
            if (cit != map.end()) {
                CommentNode child = build(kid, depth+1);
                if (child.comment.id != 0) node.children.push_back(std::move(child));
            }
        }
        return node;
    };

    std::vector<CommentNode> roots;
    roots.reserve(rootKids.size());
    for (int rid : rootKids) {
        auto it = map.find(rid);
        if (it != map.end()) {
            roots.push_back(build(rid, 0));
        }
    }
    // Filter empty (failed lookups)
    roots.erase(std::remove_if(roots.begin(), roots.end(), [](auto& n){ return n.comment.id==0; }), roots.end());
    return roots;
}

std::vector<CommentNode> HNCppEngine::buildCommentTreeFlat(
    const std::vector<HNItem>& comments
) {
    // Infer roots: comments whose id is not in any kids list
    std::unordered_set<int> allKids;
    allKids.reserve(comments.size()*2);
    for (auto& c : comments) for (int k : c.kids) allKids.insert(k);
    std::vector<int> roots;
    for (auto& c : comments) if (allKids.find(c.id) == allKids.end()) roots.push_back(c.id);
    return buildCommentTree(comments, roots);
}

void HNCppEngine::flattenTree(const std::vector<CommentNode>& nodes, std::vector<const HNItem*>& out, bool respectCollapse) {
    for (auto& n : nodes) {
        out.push_back(&n.comment);
        if (respectCollapse && n.isCollapsed) continue;
        flattenTree(n.children, out, respectCollapse);
    }
}

size_t HNCppEngine::countNodes(const std::vector<CommentNode>& nodes) {
    size_t c = 0;
    for (auto& n : nodes) c += 1 + countNodes(n.children);
    return c;
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

// MARK: - Search

std::vector<HNItem> HNCppEngine::search(
    const std::vector<HNItem>& items,
    const std::string& query
) {
    if (query.empty()) return {};
    std::string lowerQ = query;
    std::transform(lowerQ.begin(), lowerQ.end(), lowerQ.begin(), ::tolower);
    auto contains = [&](const std::optional<std::string>& field) -> bool {
        if (!field) return false;
        std::string s = *field;
        std::transform(s.begin(), s.end(), s.begin(), ::tolower);
        return s.find(lowerQ) != std::string::npos;
    };
    auto domainContains = [&](const HNItem& item) -> bool {
        std::string d = item.domain();
        std::transform(d.begin(), d.end(), d.begin(), ::tolower);
        return d.find(lowerQ) != std::string::npos;
    };
    std::vector<HNItem> out;
    for (auto& it : items) {
        if (contains(it.title) || contains(it.by) || contains(it.text) || domainContains(it)) {
            out.push_back(it);
        } else {
            // also check id
            if (std::to_string(it.id).find(lowerQ) != std::string::npos) out.push_back(it);
        }
    }
    return out;
}

// MARK: - Eviction

HNCppEngine::EvictionResult HNCppEngine::evictionPlan(
    const std::vector<HNItem>& allStories,
    const std::unordered_map<int, double>& lastFetchedMap,
    const std::unordered_set<int>& savedIDs,
    const std::unordered_set<int>& metadataIDs,
    double maxAgeSeconds,
    double cutoffAge
) {
    EvictionResult res;
    auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    for (auto& s : allStories) {
        if (savedIDs.count(s.id)) { res.keepIDs.push_back(s.id); continue; }
        if (metadataIDs.count(s.id)) { res.keepIDs.push_back(s.id); continue; }
        auto it = lastFetchedMap.find(s.id);
        double age = (it != lastFetchedMap.end()) ? (static_cast<double>(now) - it->second) : 1e9;
        if (age < cutoffAge && age < maxAgeSeconds) res.keepIDs.push_back(s.id);
        else res.evictIDs.push_back(s.id);
    }
    return res;
}

// MARK: - URL

std::string HNCppEngine::extractDomain(const std::string& url) {
    HNItem tmp; tmp.url = url;
    return tmp.domain();
}

std::string HNCppEngine::storyURL(int storyID) {
    return "https://news.ycombinator.com/item?id=" + std::to_string(storyID);
}

std::string HNCppEngine::itemEndpoint(int itemID) {
    return "item/" + std::to_string(itemID) + ".json";
}

} // namespace HackerNews
