#pragma once

#include "hn/Feed.hpp"

#include <string>
#include <vector>

namespace hn {

double nowUnix();
int64_t nowMillis();

std::string toLowerAscii(std::string value);
std::string trim(const std::string& value);
bool containsCaseInsensitive(const std::string& haystack, const std::string& needle);

/// Hacker News text is HTML. The engine owns the conversion so Swift only
/// receives presentation-ready strings.
std::string stripHtml(const std::string& html);
std::string htmlToPlainText(const std::string& html);

std::string domainFromURL(const std::string& url);
std::string timeAgoFromUnix(double unixTime);
std::string timeAgoFromSeconds(double secondsAgo);

std::string storyURL(int storyID);
std::string itemPath(int itemID);

} // namespace hn
