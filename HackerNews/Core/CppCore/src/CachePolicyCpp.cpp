#include "CachePolicyCpp.hpp"
#include <chrono>

namespace HackerNews {

CachePolicyCpp::Freshness CachePolicyCpp::freshnessForAgeSeconds(double age) {
    if (age < 0) return Freshness::Empty;
    if (age < FreshInterval) return Freshness::Fresh;
    if (age < StaleInterval) return Freshness::Stale;
    if (age < MaxAge) return Freshness::Expired;
    return Freshness::Empty;
}

CachePolicyCpp::Freshness CachePolicyCpp::freshnessForUnixTime(double unixTime) {
    if (unixTime <= 0) return Freshness::Empty;
    auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    double age = static_cast<double>(now) - unixTime;
    return freshnessForAgeSeconds(age);
}

const char* CachePolicyCpp::freshnessName(Freshness f) {
    switch (f) {
        case Freshness::Fresh: return "fresh";
        case Freshness::Stale: return "stale";
        case Freshness::Expired: return "expired";
        case Freshness::Empty: return "empty";
    }
    return "unknown";
}

} // namespace HackerNews
