#include "HNTypes.hpp"
#include <chrono>
#include <regex>

namespace HackerNews {

std::string HNItem::domain() const {
    if (!url || url->empty()) return "";
    std::string u = *url;
    // Strip scheme
    auto pos = u.find("://");
    if (pos != std::string::npos) u = u.substr(pos + 3);
    // Strip path
    pos = u.find('/');
    if (pos != std::string::npos) u = u.substr(0, pos);
    // Strip www.
    if (u.rfind("www.", 0) == 0) u = u.substr(4);
    // Strip port
    pos = u.find(':');
    if (pos != std::string::npos) u = u.substr(0, pos);
    return u;
}

double HNItem::ageSeconds() const {
    if (!time) return 1e9;
    auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    return static_cast<double>(now) - *time;
}

} // namespace HackerNews
