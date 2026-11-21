#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HNFeed) {
    HNFeedTop = 0,
    HNFeedNew = 1,
    HNFeedBest = 2,
    HNFeedAsk = 3,
    HNFeedShow = 4,
    HNFeedJobs = 5
};

typedef NS_ENUM(NSInteger, HNPhase) {
    HNPhaseIdle = 0,
    HNPhaseLoading = 1,
    HNPhaseRefreshing = 2,
    HNPhaseLoaded = 3,
    HNPhaseFailed = 4
};

typedef NS_ENUM(NSInteger, HNErrorCode) {
    HNErrorCodeNone = 0,
    HNErrorCodeOffline = 1,
    HNErrorCodeTimeout = 2,
    HNErrorCodeHttp = 3,
    HNErrorCodeDecode = 4,
    HNErrorCodeNotFound = 5,
    HNErrorCodeStore = 6,
    HNErrorCodeCancelled = 7,
    HNErrorCodeUnknown = 8
};

@interface HNError : NSObject
@property (nonatomic, assign, readonly) HNErrorCode code;
@property (nonatomic, assign, readonly) NSInteger httpStatus;
@property (nonatomic, copy, readonly) NSString *message;
@property (nonatomic, assign, readonly) BOOL retryable;
@end

@interface HNStory : NSObject
@property (nonatomic, assign, readonly) NSInteger storyID;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *author;
@property (nonatomic, copy, readonly, nullable) NSString *url;
@property (nonatomic, copy, readonly, nullable) NSString *text;
@property (nonatomic, copy, readonly) NSString *plainText;
@property (nonatomic, copy, readonly, nullable) NSString *domain;
@property (nonatomic, copy, readonly) NSString *timeAgo;
@property (nonatomic, assign, readonly) NSInteger score;
@property (nonatomic, assign, readonly) NSInteger commentCount;
@property (nonatomic, strong, readonly, nullable) NSDate *createdAt;
@property (nonatomic, assign, readonly) BOOL isDead;
@property (nonatomic, assign, readonly) BOOL isDeleted;
@property (nonatomic, assign, readonly) BOOL isSaved;
@property (nonatomic, assign, readonly) HNFeed feed;
@end

@interface HNComment : NSObject
@property (nonatomic, assign, readonly) NSInteger commentID;
@property (nonatomic, assign, readonly) NSInteger parentID;
@property (nonatomic, copy, readonly, nullable) NSString *author;
@property (nonatomic, copy, readonly, nullable) NSString *text;
@property (nonatomic, copy, readonly) NSString *plainText;
@property (nonatomic, strong, readonly, nullable) NSDate *createdAt;
@property (nonatomic, copy, readonly) NSString *timeAgo;
@property (nonatomic, assign, readonly) BOOL isDead;
@property (nonatomic, assign, readonly) BOOL isDeleted;
@property (nonatomic, assign, readonly) NSInteger depth;
@property (nonatomic, copy, readonly) NSArray<HNComment *> *children;
@end

@interface HNSavedStory : NSObject
@property (nonatomic, assign, readonly) NSInteger storyID;
@property (nonatomic, strong, readonly) NSDate *savedAt;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *author;
@property (nonatomic, copy, readonly, nullable) NSString *url;
@property (nonatomic, copy, readonly, nullable) NSString *domain;
@property (nonatomic, assign, readonly) NSInteger score;
@end

@interface HNMetrics : NSObject
@property (nonatomic, assign, readonly) unsigned long long requests;
@property (nonatomic, assign, readonly) unsigned long long failures;
@property (nonatomic, assign, readonly) unsigned long long retries;
@property (nonatomic, assign, readonly) unsigned long long bytesReceived;
@property (nonatomic, assign, readonly) unsigned long long itemsParsed;
@property (nonatomic, assign, readonly) unsigned long long cacheHits;
@property (nonatomic, assign, readonly) unsigned long long cacheMisses;
@property (nonatomic, assign, readonly) unsigned long long snapshotsEmitted;
@property (nonatomic, assign, readonly) unsigned long long commentsFetched;
@property (nonatomic, assign, readonly) unsigned long long searchQueries;
@property (nonatomic, assign, readonly) NSInteger inFlight;
@property (nonatomic, assign, readonly) double lastLatencyMs;
@property (nonatomic, assign, readonly) double averageLatencyMs;
@end

@interface HNStatus : NSObject
@property (nonatomic, assign, readonly) unsigned long long revision;
@property (nonatomic, assign, readonly) HNFeed feed;
@property (nonatomic, assign, readonly) HNPhase phase;
@property (nonatomic, assign, readonly) BOOL offline;
@property (nonatomic, strong, readonly, nullable) NSDate *lastSyncAt;
@property (nonatomic, assign, readonly) NSInteger cachedStories;
@property (nonatomic, assign, readonly) NSInteger cachedComments;
@property (nonatomic, assign, readonly) NSInteger savedCount;
@property (nonatomic, assign, readonly) NSInteger searchDocs;
@property (nonatomic, assign, readonly) long long databaseBytes;
@property (nonatomic, assign, readonly) NSTimeInterval uptimeSeconds;
@property (nonatomic, copy, readonly) NSString *coreVersion;
@property (nonatomic, strong, readonly) HNMetrics *metrics;
@end

@interface HNFeedSnapshot : NSObject
@property (nonatomic, assign, readonly) HNFeed feed;
@property (nonatomic, assign, readonly) unsigned long long revision;
@property (nonatomic, assign, readonly) HNPhase phase;
@property (nonatomic, copy, readonly) NSArray<HNStory *> *stories;
@property (nonatomic, strong, readonly, nullable) NSDate *lastSyncAt;
@property (nonatomic, assign, readonly) BOOL offline;
@property (nonatomic, assign, readonly) BOOL stale;
@property (nonatomic, strong, readonly, nullable) HNError *error;
@end

@interface HNStorySnapshot : NSObject
@property (nonatomic, assign, readonly) NSInteger storyID;
@property (nonatomic, assign, readonly) unsigned long long revision;
@property (nonatomic, assign, readonly) HNPhase phase;
@property (nonatomic, strong, readonly, nullable) HNStory *story;
@property (nonatomic, strong, readonly, nullable) HNError *error;
@end

@interface HNCommentsSnapshot : NSObject
@property (nonatomic, assign, readonly) NSInteger storyID;
@property (nonatomic, assign, readonly) unsigned long long revision;
@property (nonatomic, copy, readonly) NSArray<HNComment *> *roots;
@property (nonatomic, assign, readonly) NSInteger totalLoaded;
@property (nonatomic, assign, readonly) BOOL loading;
@property (nonatomic, assign, readonly) BOOL complete;
@property (nonatomic, strong, readonly, nullable) HNError *error;
@end

@interface HNSavedSnapshot : NSObject
@property (nonatomic, assign, readonly) unsigned long long revision;
@property (nonatomic, copy, readonly) NSArray<HNSavedStory *> *stories;
@end

@class HNEngine;

@protocol HNEngineListener <NSObject>
- (void)engine:(HNEngine *)engine didUpdateFeed:(HNFeedSnapshot *)snapshot NS_SWIFT_NAME(engine(_:didUpdateFeed:));
- (void)engine:(HNEngine *)engine didUpdateStory:(HNStorySnapshot *)snapshot NS_SWIFT_NAME(engine(_:didUpdateStory:));
- (void)engine:(HNEngine *)engine didUpdateComments:(HNCommentsSnapshot *)snapshot NS_SWIFT_NAME(engine(_:didUpdateComments:));
- (void)engine:(HNEngine *)engine didUpdateSaved:(HNSavedSnapshot *)snapshot NS_SWIFT_NAME(engine(_:didUpdateSaved:));
- (void)engine:(HNEngine *)engine didUpdateStatus:(HNStatus *)status NS_SWIFT_NAME(engine(_:didUpdateStatus:));
@end

/// Objective-C facade over the C++ engine. All listener callbacks are
/// delivered on the main queue. Commands are asynchronous and thread-safe.
@interface HNEngine : NSObject

- (instancetype)initWithDatabasePath:(NSString *)databasePath
                             baseURL:(NSString *)baseURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<HNEngineListener> listener;

- (void)start;
- (void)shutdown;

- (void)selectFeed:(HNFeed)feed NS_SWIFT_NAME(selectFeed(_:));
- (void)refreshFeed NS_SWIFT_NAME(refreshFeed());
- (void)loadMore NS_SWIFT_NAME(loadMore());
- (void)openStory:(NSInteger)storyID NS_SWIFT_NAME(openStory(_:));
- (void)refreshStory:(NSInteger)storyID NS_SWIFT_NAME(refreshStory(_:));
- (void)loadCommentsForStory:(NSInteger)storyID force:(BOOL)force NS_SWIFT_NAME(loadComments(forStory:force:));
- (void)toggleSave:(NSInteger)storyID NS_SWIFT_NAME(toggleSave(_:));
- (void)setSaved:(BOOL)saved storyID:(NSInteger)storyID NS_SWIFT_NAME(setSaved(_:storyID:));

- (BOOL)isSaved:(NSInteger)storyID NS_SWIFT_NAME(isSaved(_:));
- (NSArray<HNSavedStory *> *)savedStories NS_SWIFT_NAME(savedStories());
- (NSArray<HNStory *> *)search:(NSString *)query limit:(NSInteger)limit NS_SWIFT_NAME(search(_:limit:));
- (HNStatus *)status NS_SWIFT_NAME(status());

- (void)clearCacheKeepingSaved:(BOOL)keepSaved NS_SWIFT_NAME(clearCache(keepSaved:));
- (void)evictCache NS_SWIFT_NAME(evictCache());

- (NSString *)coreVersion NS_SWIFT_NAME(coreVersion());

@end

NS_ASSUME_NONNULL_END
