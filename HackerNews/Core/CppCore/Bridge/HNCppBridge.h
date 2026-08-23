#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ bridge to HackerNews C++ Core Engine
/// Swift calls this; implementation forwards to HackerNews::HNCppEngine (C++)
@interface HNCppBridge : NSObject

// Feed
+ (NSString *)endpointForFeed:(NSString *)feedRawValue;
+ (NSString *)iconForFeed:(NSString *)feedRawValue;
+ (NSString *)descriptionForFeed:(NSString *)feedRawValue;

// Cache
+ (NSString *)freshnessForAge:(NSTimeInterval)ageSeconds;
+ (BOOL)isFreshWithAge:(NSTimeInterval)ageSeconds;

// Algorithms
+ (NSArray<NSNumber *> *)deduplicateIDs:(NSArray<NSNumber *> *)ids;
+ (NSArray<NSArray<NSNumber *> *> *)chunkIDs:(NSArray<NSNumber *> *)ids chunkSize:(NSInteger)size;

// Text
+ (NSString *)stripHTML:(NSString *)html;
+ (NSString *)timeAgoFromUnixTime:(NSTimeInterval)unixTime;
+ (NSString *)domainFromURL:(NSString *)url;

// Story URL
+ (NSString *)storyURLForID:(NSInteger)storyID;
+ (NSString *)itemEndpointForID:(NSInteger)itemID;

// Diagnostics
+ (NSString *)cppCoreVersion;
+ (NSDictionary<NSString *, id> *)engineStatsForCommentCount:(NSInteger)count depth:(NSInteger)depth;

@end

NS_ASSUME_NONNULL_END
