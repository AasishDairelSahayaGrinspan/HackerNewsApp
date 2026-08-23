#import "HNCppBridge.h"
#import <Foundation/Foundation.h>

// C++ imports
#include "HNCppEngine.hpp"
#include "CachePolicyCpp.hpp"

using namespace HackerNews;

@implementation HNCppBridge

+ (NSString *)endpointForFeed:(NSString *)feedRawValue {
    std::string s = [feedRawValue UTF8String] ?: "";
    FeedType f = HNCppEngine::feedFromString(s);
    return [NSString stringWithUTF8String:HNCppEngine::feedEndpoint(f).c_str()];
}

+ (NSString *)iconForFeed:(NSString *)feedRawValue {
    FeedType f = HNCppEngine::feedFromString([[feedRawValue lowercaseString] UTF8String] ?: "");
    return [NSString stringWithUTF8String:HNCppEngine::feedIcon(f).c_str()];
}

+ (NSString *)descriptionForFeed:(NSString *)feedRawValue {
    FeedType f = HNCppEngine::feedFromString([feedRawValue UTF8String] ?: "");
    return [NSString stringWithUTF8String:HNCppEngine::feedDescription(f).c_str()];
}

+ (NSString *)freshnessForAge:(NSTimeInterval)ageSeconds {
    auto f = CachePolicyCpp::freshnessForAgeSeconds(ageSeconds);
    return [NSString stringWithUTF8String:CachePolicyCpp::freshnessName(f)];
}

+ (BOOL)isFreshWithAge:(NSTimeInterval)ageSeconds {
    return CachePolicyCpp::isFresh(ageSeconds);
}

+ (NSArray<NSNumber *> *)deduplicateIDs:(NSArray<NSNumber *> *)ids {
    std::vector<int> vec;
    vec.reserve(ids.count);
    for (NSNumber *n in ids) vec.push_back(n.intValue);
    auto out = HNCppEngine::deduplicateIDs(vec);
    NSMutableArray *res = [NSMutableArray arrayWithCapacity:out.size()];
    for (int v : out) [res addObject:@(v)];
    return res;
}

+ (NSArray<NSArray<NSNumber *> *> *)chunkIDs:(NSArray<NSNumber *> *)ids chunkSize:(NSInteger)size {
    std::vector<int> vec;
    vec.reserve(ids.count);
    for (NSNumber *n in ids) vec.push_back(n.intValue);
    auto chunks = HNCppEngine::chunkIDs(vec, (size_t)size);
    NSMutableArray *res = [NSMutableArray arrayWithCapacity:chunks.size()];
    for (auto &c : chunks) {
        NSMutableArray *inner = [NSMutableArray arrayWithCapacity:c.size()];
        for (int v : c) [inner addObject:@(v)];
        [res addObject:inner];
    }
    return res;
}

+ (NSString *)stripHTML:(NSString *)html {
    if (!html) return @"";
    std::string s = [html UTF8String] ?: "";
    std::string out = HNCppEngine::stripHTML(s);
    return [NSString stringWithUTF8String:out.c_str()];
}

+ (NSString *)timeAgoFromUnixTime:(NSTimeInterval)unixTime {
    std::string s = HNCppEngine::timeAgoFromUnix(unixTime);
    return [NSString stringWithUTF8String:s.c_str()];
}

+ (NSString *)domainFromURL:(NSString *)url {
    if (!url) return @"";
    std::string s = [url UTF8String] ?: "";
    std::string d = HNCppEngine::extractDomain(s);
    return [NSString stringWithUTF8String:d.c_str()];
}

+ (NSString *)storyURLForID:(NSInteger)storyID {
    std::string s = HNCppEngine::storyURL((int)storyID);
    return [NSString stringWithUTF8String:s.c_str()];
}

+ (NSString *)itemEndpointForID:(NSInteger)itemID {
    std::string s = HNCppEngine::itemEndpoint((int)itemID);
    return [NSString stringWithUTF8String:s.c_str()];
}

+ (NSString *)cppCoreVersion {
    return @"HackerNews C++ Core v1.0 (C++20) - HDDL";
}

+ (NSDictionary<NSString *, id> *)engineStatsForCommentCount:(NSInteger)count depth:(NSInteger)depth {
    return @{
        @"core": @"C++20",
        @"commentCount": @(count),
        @"depth": @(depth),
        @"maxConcurrency": @12,
        @"chunkSize": @25,
        @"hardCap": @400
    };
}

@end
