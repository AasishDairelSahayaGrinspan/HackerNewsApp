#include "hn/Text.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace hn {

// MARK: - Feed mapping

const char* feedPath(Feed feed) {
    switch (feed) {
        case Feed::Top: return "topstories.json";
        case Feed::New: return "newstories.json";
        case Feed::Best: return "beststories.json";
        case Feed::Ask: return "askstories.json";
        case Feed::Show: return "showstories.json";
        case Feed::Jobs: return "jobstories.json";
    }
    return "topstories.json";
}

const char* feedName(Feed feed) {
    switch (feed) {
        case Feed::Top: return "Top";
        case Feed::New: return "New";
        case Feed::Best: return "Best";
        case Feed::Ask: return "Ask";
        case Feed::Show: return "Show";
        case Feed::Jobs: return "Jobs";
    }
    return "Top";
}

const char* feedDescription(Feed feed) {
    switch (feed) {
        case Feed::Top: return "Most popular stories right now";
        case Feed::New: return "Fresh submissions";
        case Feed::Best: return "Highest voted stories";
        case Feed::Ask: return "Ask Hacker News";
        case Feed::Show: return "Show your work";
        case Feed::Jobs: return "Who is hiring";
    }
    return "";
}

Feed feedFromInt(int value) {
    switch (value) {
        case 1: return Feed::New;
        case 2: return Feed::Best;
        case 3: return Feed::Ask;
        case 4: return Feed::Show;
        case 5: return Feed::Jobs;
        default: return Feed::Top;
    }
}

// MARK: - Time

double nowUnix() {
    using namespace std::chrono;
    return duration<double>(system_clock::now().time_since_epoch()).count();
}

int64_t nowMillis() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

// MARK: - Strings

std::string toLowerAscii(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

std::string trim(const std::string& value) {
    const auto start = value.find_first_not_of(" \n\r\t");
    if (start == std::string::npos) return "";
    const auto end = value.find_last_not_of(" \n\r\t");
    return value.substr(start, end - start + 1);
}

bool containsCaseInsensitive(const std::string& haystack, const std::string& needle) {
    if (needle.empty()) return true;
    const std::string h = toLowerAscii(haystack);
    const std::string n = toLowerAscii(needle);
    return h.find(n) != std::string::npos;
}

// MARK: - HTML

namespace {

void replaceAll(std::string& value, const std::string& from, const std::string& to) {
    if (from.empty()) return;
    size_t pos = 0;
    while ((pos = value.find(from, pos)) != std::string::npos) {
        value.replace(pos, from.size(), to);
        pos += to.size();
    }
}

std::string decodeEntities(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    size_t i = 0;
    while (i < input.size()) {
        if (input[i] != '&') {
            out.push_back(input[i++]);
            continue;
        }
        const size_t semicolon = input.find(';', i + 1);
        if (semicolon == std::string::npos || semicolon - i > 12) {
            out.push_back(input[i++]);
            continue;
        }
        const std::string entity = input.substr(i + 1, semicolon - i - 1);
        bool handled = true;
        if (entity == "amp") out.push_back('&');
        else if (entity == "lt") out.push_back('<');
        else if (entity == "gt") out.push_back('>');
        else if (entity == "quot") out.push_back('"');
        else if (entity == "apos") out.push_back('\'');
        else if (entity == "nbsp") out.push_back(' ');
        else if (entity == "#x27" || entity == "#X27") out.push_back('\'');
        else if (entity == "#x2F" || entity == "#X2F") out.push_back('/');
        else if (entity == "#x3D" || entity == "#X3D") out.push_back('=');
        else if (entity == "#x60" || entity == "#X60") out.push_back('`');
        else if (entity == "#39") out.push_back('\'');
        else if (entity == "#47") out.push_back('/');
        else if (entity == "#61") out.push_back('=');
        else if (entity == "#96") out.push_back('`');
        else handled = false;

        if (handled) {
            i = semicolon + 1;
            continue;
        }

        // Numeric decimal entity (&#123;)
        if (entity.size() > 1 && entity[0] == '#') {
            char* end = nullptr;
            long code = 0;
            if (entity[1] == 'x' || entity[1] == 'X') {
                code = std::strtol(entity.c_str() + 2, &end, 16);
            } else {
                code = std::strtol(entity.c_str() + 1, &end, 10);
            }
            if (end && *end == '\0' && code > 0 && code < 0x110000) {
                // Encode as UTF-8.
                if (code <= 0x7F) {
                    out.push_back(static_cast<char>(code));
                } else if (code <= 0x7FF) {
                    out.push_back(static_cast<char>(0xC0 | (code >> 6)));
                    out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
                } else if (code <= 0xFFFF) {
                    out.push_back(static_cast<char>(0xE0 | (code >> 12)));
                    out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
                    out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
                } else {
                    out.push_back(static_cast<char>(0xF0 | (code >> 18)));
                    out.push_back(static_cast<char>(0x80 | ((code >> 12) & 0x3F)));
                    out.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
                    out.push_back(static_cast<char>(0x80 | (code & 0x3F)));
                }
                i = semicolon + 1;
                continue;
            }
        }

        out.push_back(input[i++]);
    }
    return out;
}

} // namespace

std::string stripHtml(const std::string& html) {
    if (html.empty()) return "";

    // Preserve paragraph boundaries before removing tags.
    std::string prepared = html;
    replaceAll(prepared, "<p>", "\n\n");
    replaceAll(prepared, "<P>", "\n\n");
    replaceAll(prepared, "</p>", "\n");
    replaceAll(prepared, "<br>", "\n");
    replaceAll(prepared, "<br/>", "\n");
    replaceAll(prepared, "<br />", "\n");
    replaceAll(prepared, "<BR>", "\n");
    replaceAll(prepared, "<BR/>", "\n");

    std::string withoutTags;
    withoutTags.reserve(prepared.size());
    bool inTag = false;
    for (char ch : prepared) {
        if (ch == '<') {
            inTag = true;
            continue;
        }
        if (ch == '>') {
            inTag = false;
            continue;
        }
        if (!inTag) withoutTags.push_back(ch);
    }

    std::string decoded = decodeEntities(withoutTags);

    // Normalize excessive blank lines.
    std::string normalized;
    normalized.reserve(decoded.size());
    int newlineRun = 0;
    for (char ch : decoded) {
        if (ch == '\n') {
            ++newlineRun;
            if (newlineRun <= 2) normalized.push_back(ch);
        } else {
            newlineRun = 0;
            normalized.push_back(ch);
        }
    }
    return trim(normalized);
}

std::string htmlToPlainText(const std::string& html) {
    return stripHtml(html);
}

// MARK: - URL

std::string domainFromURL(const std::string& url) {
    std::string value = trim(url);
    if (value.empty()) return "";

    // HN occasionally has bare domains. Reject free text early.
    if (value.find_first_of(" \t\n\r") != std::string::npos) return "";

    std::string scheme;
    const size_t schemePos = value.find("://");
    if (schemePos != std::string::npos) {
        scheme = toLowerAscii(value.substr(0, schemePos));
        if (scheme != "http" && scheme != "https") return "";
        value = value.substr(schemePos + 3);
    } else {
        // A URL without a scheme is only accepted if it looks like a host.
        if (value.rfind("//", 0) == 0) value = value.substr(2);
        if (value.find('.') == std::string::npos) return "";
    }

    // Strip credentials.
    const size_t at = value.find('@');
    if (at != std::string::npos) value = value.substr(at + 1);

    // Strip path, query and fragment.
    size_t end = value.find_first_of("/?#");
    if (end != std::string::npos) value = value.substr(0, end);

    // Strip port.
    const size_t colon = value.find(':');
    if (colon != std::string::npos) value = value.substr(0, colon);

    value = toLowerAscii(value);
    while (!value.empty() && value.back() == '.') value.pop_back();
    if (value.rfind("www.", 0) == 0) value = value.substr(4);

    if (value.empty() || value.find('.') == std::string::npos) return "";
    if (value.front() == '.' || value.back() == '.') return "";
    if (value.find_first_of(" \t\n\r") != std::string::npos) return "";
    return value;
}

// MARK: - Relative time

std::string timeAgoFromSeconds(double secondsAgo) {
    if (secondsAgo < 0) secondsAgo = 0;
    if (secondsAgo < 60) {
        return std::to_string(static_cast<int>(secondsAgo)) + "s ago";
    }
    if (secondsAgo < 3600) {
        return std::to_string(static_cast<int>(secondsAgo / 60)) + "m ago";
    }
    if (secondsAgo < 86400) {
        return std::to_string(static_cast<int>(secondsAgo / 3600)) + "h ago";
    }
    if (secondsAgo < 86400 * 30) {
        return std::to_string(static_cast<int>(secondsAgo / 86400)) + "d ago";
    }
    if (secondsAgo < 86400 * 365) {
        return std::to_string(static_cast<int>(secondsAgo / (86400 * 30))) + "mo ago";
    }
    return std::to_string(static_cast<int>(secondsAgo / (86400 * 365))) + "y ago";
}

std::string timeAgoFromUnix(double unixTime) {
    if (unixTime <= 0) return "unknown";
    return timeAgoFromSeconds(nowUnix() - unixTime);
}

// MARK: - URLs

std::string storyURL(int storyID) {
    return "https://news.ycombinator.com/item?id=" + std::to_string(storyID);
}

std::string itemPath(int itemID) {
    return "item/" + std::to_string(itemID) + ".json";
}

} // namespace hn
