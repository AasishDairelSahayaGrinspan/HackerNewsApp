#pragma once
#include <string>
#include <vector>
#include <optional>
#include <chrono>

namespace HackerNews {

enum class FeedType {
    Top,
    New,
    Best,
    Ask,
    Show,
    Jobs
};

struct HNItem {
    int id = 0;
    std::optional<std::string> type;
    std::optional<std::string> by;
    std::optional<double> time; // unix seconds
    std::optional<std::string> title;
    std::optional<std::string> url;
    std::optional<std::string> text;
    std::optional<int> score;
    std::optional<int> descendants;
    std::vector<int> kids;
    std::vector<int> parts;
    std::optional<int> parent;
    std::optional<int> poll;
    bool deleted = false;
    bool dead = false;

    // Helpers
    std::string domain() const;
    double ageSeconds() const;
    bool isStory() const { return type && *type == "story"; }
    bool isComment() const { return type && *type == "comment"; }
};

// Comment tree node for C++ core
struct CommentNode {
    HNItem comment;
    std::vector<CommentNode> children;
    int depth = 0;
    bool isCollapsed = false;

    bool operator==(const CommentNode& other) const {
        return comment.id == other.comment.id && isCollapsed == other.isCollapsed && children == other.children;
    }
};

} // namespace HackerNews
