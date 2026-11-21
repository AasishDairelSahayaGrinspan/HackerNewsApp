#pragma once

namespace hn {

/// Single source of truth for cache freshness. Swift no longer owns any
/// retention constants.
class CachePolicy {
public:
    static constexpr double FreshInterval = 5 * 60;
    static constexpr double StaleInterval = 30 * 60;
    static constexpr double MaxAge = 24 * 60 * 60;

    enum class Freshness {
        Fresh,
        Stale,
        Expired,
        Empty
    };

    static Freshness freshnessForAge(double ageSeconds) {
        if (ageSeconds < 0) return Freshness::Empty;
        if (ageSeconds < FreshInterval) return Freshness::Fresh;
        if (ageSeconds < StaleInterval) return Freshness::Stale;
        if (ageSeconds < MaxAge) return Freshness::Expired;
        return Freshness::Empty;
    }

    static Freshness freshnessForFetchedAt(double fetchedAtUnix, double nowUnix);
    static bool isFresh(double ageSeconds) {
        return freshnessForAge(ageSeconds) == Freshness::Fresh;
    }
    static const char* name(Freshness freshness);
};

} // namespace hn
