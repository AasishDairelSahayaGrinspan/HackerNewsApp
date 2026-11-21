#import "HNEngine.h"

#import <Foundation/Foundation.h>

#include "hn/AppleTransport.hpp"
#include "hn/Engine.hpp"
#include "hn/Text.hpp"

#include <memory>

using namespace hn;

// MARK: - Read-write model internals

@interface HNError ()
@property (nonatomic, assign, readwrite) HNErrorCode code;
@property (nonatomic, assign, readwrite) NSInteger httpStatus;
@property (nonatomic, copy, readwrite) NSString *message;
@property (nonatomic, assign, readwrite) BOOL retryable;
@end

@interface HNStory ()
@property (nonatomic, assign, readwrite) NSInteger storyID;
@property (nonatomic, copy, readwrite, nullable) NSString *title;
@property (nonatomic, copy, readwrite, nullable) NSString *author;
@property (nonatomic, copy, readwrite, nullable) NSString *url;
@property (nonatomic, copy, readwrite, nullable) NSString *text;
@property (nonatomic, copy, readwrite) NSString *plainText;
@property (nonatomic, copy, readwrite, nullable) NSString *domain;
@property (nonatomic, copy, readwrite) NSString *timeAgo;
@property (nonatomic, assign, readwrite) NSInteger score;
@property (nonatomic, assign, readwrite) NSInteger commentCount;
@property (nonatomic, strong, readwrite, nullable) NSDate *createdAt;
@property (nonatomic, assign, readwrite) BOOL isDead;
@property (nonatomic, assign, readwrite) BOOL isDeleted;
@property (nonatomic, assign, readwrite) BOOL isSaved;
@property (nonatomic, assign, readwrite) HNFeed feed;
@end

@interface HNComment ()
@property (nonatomic, assign, readwrite) NSInteger commentID;
@property (nonatomic, assign, readwrite) NSInteger parentID;
@property (nonatomic, copy, readwrite, nullable) NSString *author;
@property (nonatomic, copy, readwrite, nullable) NSString *text;
@property (nonatomic, copy, readwrite) NSString *plainText;
@property (nonatomic, strong, readwrite, nullable) NSDate *createdAt;
@property (nonatomic, copy, readwrite) NSString *timeAgo;
@property (nonatomic, assign, readwrite) BOOL isDead;
@property (nonatomic, assign, readwrite) BOOL isDeleted;
@property (nonatomic, assign, readwrite) NSInteger depth;
@property (nonatomic, copy, readwrite) NSArray<HNComment *> *children;
@end

@interface HNSavedStory ()
@property (nonatomic, assign, readwrite) NSInteger storyID;
@property (nonatomic, strong, readwrite) NSDate *savedAt;
@property (nonatomic, copy, readwrite, nullable) NSString *title;
@property (nonatomic, copy, readwrite, nullable) NSString *author;
@property (nonatomic, copy, readwrite, nullable) NSString *url;
@property (nonatomic, copy, readwrite, nullable) NSString *domain;
@property (nonatomic, assign, readwrite) NSInteger score;
@end

@interface HNMetrics ()
@property (nonatomic, assign, readwrite) unsigned long long requests;
@property (nonatomic, assign, readwrite) unsigned long long failures;
@property (nonatomic, assign, readwrite) unsigned long long retries;
@property (nonatomic, assign, readwrite) unsigned long long bytesReceived;
@property (nonatomic, assign, readwrite) unsigned long long itemsParsed;
@property (nonatomic, assign, readwrite) unsigned long long cacheHits;
@property (nonatomic, assign, readwrite) unsigned long long cacheMisses;
@property (nonatomic, assign, readwrite) unsigned long long snapshotsEmitted;
@property (nonatomic, assign, readwrite) unsigned long long commentsFetched;
@property (nonatomic, assign, readwrite) unsigned long long searchQueries;
@property (nonatomic, assign, readwrite) NSInteger inFlight;
@property (nonatomic, assign, readwrite) double lastLatencyMs;
@property (nonatomic, assign, readwrite) double averageLatencyMs;
@end

@interface HNStatus ()
@property (nonatomic, assign, readwrite) unsigned long long revision;
@property (nonatomic, assign, readwrite) HNFeed feed;
@property (nonatomic, assign, readwrite) HNPhase phase;
@property (nonatomic, assign, readwrite) BOOL offline;
@property (nonatomic, strong, readwrite, nullable) NSDate *lastSyncAt;
@property (nonatomic, assign, readwrite) NSInteger cachedStories;
@property (nonatomic, assign, readwrite) NSInteger cachedComments;
@property (nonatomic, assign, readwrite) NSInteger savedCount;
@property (nonatomic, assign, readwrite) NSInteger searchDocs;
@property (nonatomic, assign, readwrite) long long databaseBytes;
@property (nonatomic, assign, readwrite) NSTimeInterval uptimeSeconds;
@property (nonatomic, copy, readwrite) NSString *coreVersion;
@property (nonatomic, strong, readwrite) HNMetrics *metrics;
@end

@interface HNFeedSnapshot ()
@property (nonatomic, assign, readwrite) HNFeed feed;
@property (nonatomic, assign, readwrite) unsigned long long revision;
@property (nonatomic, assign, readwrite) HNPhase phase;
@property (nonatomic, copy, readwrite) NSArray<HNStory *> *stories;
@property (nonatomic, strong, readwrite, nullable) NSDate *lastSyncAt;
@property (nonatomic, assign, readwrite) BOOL offline;
@property (nonatomic, assign, readwrite) BOOL stale;
@property (nonatomic, strong, readwrite, nullable) HNError *error;
@end

@interface HNStorySnapshot ()
@property (nonatomic, assign, readwrite) NSInteger storyID;
@property (nonatomic, assign, readwrite) unsigned long long revision;
@property (nonatomic, assign, readwrite) HNPhase phase;
@property (nonatomic, strong, readwrite, nullable) HNStory *story;
@property (nonatomic, strong, readwrite, nullable) HNError *error;
@end

@interface HNCommentsSnapshot ()
@property (nonatomic, assign, readwrite) NSInteger storyID;
@property (nonatomic, assign, readwrite) unsigned long long revision;
@property (nonatomic, copy, readwrite) NSArray<HNComment *> *roots;
@property (nonatomic, assign, readwrite) NSInteger totalLoaded;
@property (nonatomic, assign, readwrite) BOOL loading;
@property (nonatomic, assign, readwrite) BOOL complete;
@property (nonatomic, strong, readwrite, nullable) HNError *error;
@end

@interface HNSavedSnapshot ()
@property (nonatomic, assign, readwrite) unsigned long long revision;
@property (nonatomic, copy, readwrite) NSArray<HNSavedStory *> *stories;
@end

@implementation HNError
@end

@implementation HNStory
@end

@implementation HNComment
@end

@implementation HNSavedStory
@end

@implementation HNMetrics
@end

@implementation HNStatus
@end

@implementation HNFeedSnapshot
@end

@implementation HNStorySnapshot
@end

@implementation HNCommentsSnapshot
@end

@implementation HNSavedSnapshot
@end

// MARK: - Conversion helpers

static NSString * _Nullable HNString(const std::string& value) {
    if (value.empty()) return nil;
    return [NSString stringWithUTF8String:value.c_str()];
}

static NSString *HNStringOrEmpty(const std::string& value) {
    return HNString(value) ?: @"";
}

static NSDate * _Nullable HNDate(double unixTime) {
    if (unixTime <= 0) return nil;
    return [NSDate dateWithTimeIntervalSince1970:unixTime];
}

static HNFeed HNFeedFrom(Feed feed) {
    return static_cast<HNFeed>(static_cast<int>(feed));
}

static HNPhase HNPhaseFrom(Phase phase) {
    return static_cast<HNPhase>(static_cast<int>(phase));
}

static HNError * _Nullable HNErrorFrom(const Error& error) {
    if (error.code == ErrorCode::None) return nil;
    HNError *object = [HNError new];
    object.code = static_cast<HNErrorCode>(static_cast<int>(error.code));
    object.httpStatus = error.httpStatus;
    object.message = HNStringOrEmpty(error.message);
    object.retryable = error.retryable;
    return object;
}

static HNStory *HNStoryFrom(const Story& story) {
    HNStory *object = [HNStory new];
    object.storyID = story.id;
    object.title = HNString(story.title);
    object.author = HNString(story.author);
    object.url = HNString(story.url);
    object.text = HNString(story.text);
    object.plainText = HNStringOrEmpty(stripHtml(story.text));
    object.domain = HNString(story.domain);
    object.timeAgo = HNStringOrEmpty(story.timeAgo.empty() ? timeAgoFromUnix(story.createdAt) : story.timeAgo);
    object.score = story.score;
    object.commentCount = story.commentCount;
    object.createdAt = HNDate(story.createdAt);
    object.isDead = story.dead;
    object.isDeleted = story.deleted;
    object.isSaved = story.saved;
    object.feed = HNFeedFrom(story.feed);
    return object;
}

static HNComment *HNCommentFrom(const CommentNode& node) {
    HNComment *object = [HNComment new];
    object.commentID = node.comment.id;
    object.parentID = node.comment.parentId;
    object.author = HNString(node.comment.author);
    object.text = HNString(node.comment.text);
    object.plainText = HNStringOrEmpty(stripHtml(node.comment.text));
    object.createdAt = HNDate(node.comment.createdAt);
    object.timeAgo = HNStringOrEmpty(timeAgoFromUnix(node.comment.createdAt));
    object.isDead = node.comment.dead;
    object.isDeleted = node.comment.deleted;
    object.depth = node.depth;

    NSMutableArray<HNComment *> *children = [NSMutableArray arrayWithCapacity:node.children.size()];
    for (const auto& child : node.children) {
        [children addObject:HNCommentFrom(child)];
    }
    object.children = children;
    return object;
}

static HNSavedStory *HNSavedStoryFrom(const SavedStory& saved) {
    HNSavedStory *object = [HNSavedStory new];
    object.storyID = saved.storyId;
    object.savedAt = HNDate(saved.savedAt) ?: [NSDate date];
    object.title = HNString(saved.title);
    object.author = HNString(saved.author);
    object.url = HNString(saved.url);
    object.domain = HNString(saved.domain);
    object.score = saved.score;
    return object;
}

static HNMetrics *HNMetricsFrom(const Metrics& metrics) {
    HNMetrics *object = [HNMetrics new];
    object.requests = metrics.requests;
    object.failures = metrics.failures;
    object.retries = metrics.retries;
    object.bytesReceived = metrics.bytesReceived;
    object.itemsParsed = metrics.itemsParsed;
    object.cacheHits = metrics.cacheHits;
    object.cacheMisses = metrics.cacheMisses;
    object.snapshotsEmitted = metrics.snapshotsEmitted;
    object.commentsFetched = metrics.commentsFetched;
    object.searchQueries = metrics.searchQueries;
    object.inFlight = metrics.inFlight;
    object.lastLatencyMs = metrics.lastLatencyMs;
    object.averageLatencyMs = metrics.averageLatencyMs();
    return object;
}

static HNStatus *HNStatusFrom(const Status& status) {
    HNStatus *object = [HNStatus new];
    object.revision = status.revision;
    object.feed = HNFeedFrom(status.feed);
    object.phase = HNPhaseFrom(status.phase);
    object.offline = status.offline;
    object.lastSyncAt = HNDate(status.lastSyncAt);
    object.cachedStories = status.cachedStories;
    object.cachedComments = status.cachedComments;
    object.savedCount = status.savedCount;
    object.searchDocs = status.searchDocs;
    object.databaseBytes = status.databaseBytes;
    object.uptimeSeconds = status.uptimeSeconds;
    object.coreVersion = HNStringOrEmpty(status.coreVersion);
    object.metrics = HNMetricsFrom(status.metrics);
    return object;
}

static HNFeedSnapshot *HNFeedSnapshotFrom(const FeedSnapshot& snapshot) {
    HNFeedSnapshot *object = [HNFeedSnapshot new];
    object.feed = HNFeedFrom(snapshot.feed);
    object.revision = snapshot.revision;
    object.phase = HNPhaseFrom(snapshot.phase);
    NSMutableArray<HNStory *> *stories = [NSMutableArray arrayWithCapacity:snapshot.stories.size()];
    for (const auto& story : snapshot.stories) [stories addObject:HNStoryFrom(story)];
    object.stories = stories;
    object.lastSyncAt = HNDate(snapshot.lastSyncAt);
    object.offline = snapshot.offline;
    object.stale = snapshot.stale;
    object.error = HNErrorFrom(snapshot.error);
    return object;
}

static HNStorySnapshot *HNStorySnapshotFrom(const StorySnapshot& snapshot) {
    HNStorySnapshot *object = [HNStorySnapshot new];
    object.storyID = snapshot.storyId;
    object.revision = snapshot.revision;
    object.phase = HNPhaseFrom(snapshot.phase);
    object.story = snapshot.story ? HNStoryFrom(*snapshot.story) : nil;
    object.error = HNErrorFrom(snapshot.error);
    return object;
}

static HNCommentsSnapshot *HNCommentsSnapshotFrom(const CommentsSnapshot& snapshot) {
    HNCommentsSnapshot *object = [HNCommentsSnapshot new];
    object.storyID = snapshot.storyId;
    object.revision = snapshot.revision;
    NSMutableArray<HNComment *> *roots = [NSMutableArray arrayWithCapacity:snapshot.roots.size()];
    for (const auto& root : snapshot.roots) [roots addObject:HNCommentFrom(root)];
    object.roots = roots;
    object.totalLoaded = snapshot.totalLoaded;
    object.loading = snapshot.loading;
    object.complete = snapshot.complete;
    object.error = HNErrorFrom(snapshot.error);
    return object;
}

static HNSavedSnapshot *HNSavedSnapshotFrom(const SavedSnapshot& snapshot) {
    HNSavedSnapshot *object = [HNSavedSnapshot new];
    object.revision = snapshot.revision;
    NSMutableArray<HNSavedStory *> *stories = [NSMutableArray arrayWithCapacity:snapshot.stories.size()];
    for (const auto& story : snapshot.stories) [stories addObject:HNSavedStoryFrom(story)];
    object.stories = stories;
    return object;
}

// MARK: - Listener proxy

@class HNEngineBridgeListener;

@interface HNEngineBridgeListener : NSObject
@property (nonatomic, weak, nullable) HNEngine *engine;
@property (nonatomic, weak, nullable) id<HNEngineListener> target;
- (void)emitFeed:(const hn::FeedSnapshot &)snapshot;
- (void)emitStory:(const hn::StorySnapshot &)snapshot;
- (void)emitComments:(const hn::CommentsSnapshot &)snapshot;
- (void)emitSaved:(const hn::SavedSnapshot &)snapshot;
- (void)emitStatus:(const hn::Status &)status;
@end

@implementation HNEngineBridgeListener

- (void)emitFeed:(const hn::FeedSnapshot &)snapshot {
    @autoreleasepool {
        HNFeedSnapshot *object = HNFeedSnapshotFrom(snapshot);
        [self deliver:object selector:@selector(engine:didUpdateFeed:)];
    }
}

- (void)emitStory:(const hn::StorySnapshot &)snapshot {
    @autoreleasepool {
        HNStorySnapshot *object = HNStorySnapshotFrom(snapshot);
        [self deliver:object selector:@selector(engine:didUpdateStory:)];
    }
}

- (void)emitComments:(const hn::CommentsSnapshot &)snapshot {
    @autoreleasepool {
        HNCommentsSnapshot *object = HNCommentsSnapshotFrom(snapshot);
        [self deliver:object selector:@selector(engine:didUpdateComments:)];
    }
}

- (void)emitSaved:(const hn::SavedSnapshot &)snapshot {
    @autoreleasepool {
        HNSavedSnapshot *object = HNSavedSnapshotFrom(snapshot);
        [self deliver:object selector:@selector(engine:didUpdateSaved:)];
    }
}

- (void)emitStatus:(const hn::Status &)status {
    @autoreleasepool {
        HNStatus *object = HNStatusFrom(status);
        [self deliver:object selector:@selector(engine:didUpdateStatus:)];
    }
}

- (void)deliver:(id)object selector:(SEL)selector {
    __weak HNEngine *engine = self.engine;
    __weak id<HNEngineListener> target = self.target;
    dispatch_async(dispatch_get_main_queue(), ^{
        HNEngine *strongEngine = engine;
        id<HNEngineListener> strongTarget = target;
        if (!strongEngine || !strongTarget) return;
        if ([strongTarget respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [strongTarget performSelector:selector withObject:strongEngine withObject:object];
#pragma clang diagnostic pop
        }
    });
}

@end

class BridgeListener final : public hn::Engine::Listener {
public:
    explicit BridgeListener(HNEngineBridgeListener *proxy) : proxy_(proxy) {}

    void onFeed(const hn::FeedSnapshot& snapshot) override {
        [proxy_ emitFeed:snapshot];
    }
    void onStory(const hn::StorySnapshot& snapshot) override {
        [proxy_ emitStory:snapshot];
    }
    void onComments(const hn::CommentsSnapshot& snapshot) override {
        [proxy_ emitComments:snapshot];
    }
    void onSaved(const hn::SavedSnapshot& snapshot) override {
        [proxy_ emitSaved:snapshot];
    }
    void onStatus(const hn::Status& status) override {
        [proxy_ emitStatus:status];
    }

private:
    HNEngineBridgeListener *proxy_;
};

// MARK: - Engine

@interface HNEngine ()
@property (nonatomic, strong) HNEngineBridgeListener *proxy;
@end

@implementation HNEngine {
    std::unique_ptr<hn::Engine> _engine;
    std::unique_ptr<BridgeListener> _adapter;
}

- (instancetype)initWithDatabasePath:(NSString *)databasePath baseURL:(NSString *)baseURL {
    self = [super init];
    if (self) {
        _proxy = [HNEngineBridgeListener new];
        _proxy.engine = self;
        _adapter = std::make_unique<BridgeListener>(_proxy);

        const char *path = databasePath.UTF8String ?: ":memory:";
        const char *url = baseURL.UTF8String ?: "https://hacker-news.firebaseio.com/v0/";
        _engine = std::make_unique<hn::Engine>(path, url, hn::makeAppleTransport());
        _engine->setListener(_adapter.get());
    }
    return self;
}

- (void)dealloc {
    if (_engine) {
        _engine->setListener(nullptr);
        _engine->shutdown();
    }
    _adapter.reset();
    _engine.reset();
}

- (id<HNEngineListener>)listener {
    return _proxy.target;
}

- (void)setListener:(id<HNEngineListener>)listener {
    _proxy.target = listener;
}

- (void)start {
    _engine->start();
}

- (void)shutdown {
    _engine->shutdown();
}

- (void)selectFeed:(HNFeed)feed {
    _engine->selectFeed(static_cast<hn::Feed>(feed));
}

- (void)refreshFeed {
    _engine->refreshFeed();
}

- (void)loadMore {
    _engine->loadMore();
}

- (void)openStory:(NSInteger)storyID {
    _engine->openStory(static_cast<int>(storyID));
}

- (void)refreshStory:(NSInteger)storyID {
    _engine->refreshStory(static_cast<int>(storyID));
}

- (void)loadCommentsForStory:(NSInteger)storyID force:(BOOL)force {
    _engine->loadComments(static_cast<int>(storyID), force);
}

- (void)toggleSave:(NSInteger)storyID {
    _engine->toggleSave(static_cast<int>(storyID));
}

- (void)setSaved:(BOOL)saved storyID:(NSInteger)storyID {
    _engine->setSaved(static_cast<int>(storyID), saved);
}

- (BOOL)isSaved:(NSInteger)storyID {
    return _engine->isSaved(static_cast<int>(storyID));
}

- (NSArray<HNSavedStory *> *)savedStories {
    const auto stories = _engine->savedStories();
    NSMutableArray<HNSavedStory *> *result = [NSMutableArray arrayWithCapacity:stories.size()];
    for (const auto& story : stories) [result addObject:HNSavedStoryFrom(story)];
    return result;
}

- (NSArray<HNStory *> *)search:(NSString *)query limit:(NSInteger)limit {
    const char *text = query.UTF8String ?: "";
    const auto stories = _engine->search(text, static_cast<int>(limit));
    NSMutableArray<HNStory *> *result = [NSMutableArray arrayWithCapacity:stories.size()];
    for (const auto& story : stories) [result addObject:HNStoryFrom(story)];
    return result;
}

- (HNStatus *)status {
    return HNStatusFrom(_engine->status());
}

- (void)clearCacheKeepingSaved:(BOOL)keepSaved {
    _engine->clearCache(keepSaved);
}

- (void)evictCache {
    _engine->evictCache();
}

- (NSString *)coreVersion {
    return HNStringOrEmpty(_engine->version());
}

@end
