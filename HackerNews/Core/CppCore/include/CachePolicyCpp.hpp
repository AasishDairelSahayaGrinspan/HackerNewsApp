#pragma once
#include <chrono>

namespace HackerNews {

class CachePolicyCpp {
public:
    static constexpr double FreshInterval = 5 * 60;      // 5 min
    static constexpr double StaleInterval = 30 * 60;     // 30 min
    static constexpr double MaxAge = 24 * 60 * 60;       // 24h

    enum class Freshness {
        Fresh,
        Stale,
        Expired,
        Empty
    };

    static Freshness freshnessForAgeSeconds(double ageSeconds);
    static Freshness freshnessForUnixTime(double unixTime); // unixTime = 0 means empty
    static bool isFresh(double ageSeconds) { return freshnessForAgeSeconds(ageSeconds) == Freshness::Fresh; }
    static const char* freshnessName(Freshness f);
};

} // namespace HackerNews
