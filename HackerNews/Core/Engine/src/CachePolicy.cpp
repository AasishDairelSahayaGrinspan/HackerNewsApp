#include "hn/CachePolicy.hpp"

namespace hn {

CachePolicy::Freshness CachePolicy::freshnessForFetchedAt(double fetchedAtUnix, double nowUnix) {
    if (fetchedAtUnix <= 0) return Freshness::Empty;
    return freshnessForAge(nowUnix - fetchedAtUnix);
}

const char* CachePolicy::name(Freshness freshness) {
    switch (freshness) {
        case Freshness::Fresh: return "fresh";
        case Freshness::Stale: return "stale";
        case Freshness::Expired: return "expired";
        case Freshness::Empty: return "empty";
    }
    return "unknown";
}

} // namespace hn
