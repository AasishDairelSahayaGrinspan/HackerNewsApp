#import <XCTest/XCTest.h>

#include "hn/CachePolicy.hpp"
#include "hn/Dispatcher.hpp"
#include "hn/Feed.hpp"
#include "hn/Json.hpp"
#include "hn/SearchIndex.hpp"
#include "hn/Store.hpp"
#include "hn/Text.hpp"
#include "hn/Tree.hpp"

#include <string>
#include <vector>

@interface HNCoreTests : XCTestCase
@end

@implementation HNCoreTests

#pragma mark - JSON

- (void)testJsonParsesObjectsArraysAndUnicode {
    const std::string text =
        R"({"id":123,"title":"Hello \u00e9 \ud83d\ude00","kids":[1,2,3],"dead":false,"none":null})";
    hn::Json json;
    std::string error;
    XCTAssertTrue(hn::Json::parse(text, json, &error));
    XCTAssertTrue(error.empty());
    XCTAssertTrue(json.isObject());
    XCTAssertEqual(json.find("id")->intOr(), 123);
    XCTAssertTrue(json.find("title")->stringOr() == "Hello \xC3\xA9 \xF0\x9F\x98\x80");
    XCTAssertEqual(json.find("kids")->array.size(), static_cast<size_t>(3));
    XCTAssertEqual(json.find("kids")->array[2].intOr(), 3);
    XCTAssertFalse(json.find("dead")->boolOr(true));
    XCTAssertTrue(json.find("none")->isNull());
    XCTAssertTrue(json.find("missing") == nullptr);
}

- (void)testJsonRejectsMalformedInput {
    hn::Json json;
    std::string error;
    XCTAssertFalse(hn::Json::parse("{\"id\":}", json, &error));
    XCTAssertFalse(error.empty());
    XCTAssertFalse(hn::Json::parse("", json, &error));
    XCTAssertFalse(hn::Json::parse("[1,2,", json, &error));
}

- (void)testIntArrayRoundTrip {
    const std::vector<int> values{4, 8, 15, 16, 23, 42};
    const std::string encoded = hn::jsonIntArray(values);
    XCTAssertTrue(encoded == "[4,8,15,16,23,42]");

    std::vector<int> decoded;
    XCTAssertTrue(hn::parseIntArray(encoded, decoded));
    XCTAssertEqual(decoded.size(), values.size());
    XCTAssertTrue(decoded == values);

    std::vector<int> empty;
    XCTAssertTrue(hn::parseIntArray("", empty));
    XCTAssertTrue(empty.empty());
    XCTAssertFalse(hn::parseIntArray("[1,\"two\"]", decoded));
}

#pragma mark - Text

- (void)testHtmlStrippingAndEntities {
    const std::string html =
        "<p>Hello &amp; welcome</p><p>Second <i>line</i><br>break</p>";
    const std::string plain = hn::stripHtml(html);
    XCTAssertTrue(plain == "Hello & welcome\n\nSecond line\nbreak");
    XCTAssertTrue(hn::stripHtml("").empty());
    XCTAssertTrue(hn::stripHtml("<p>  spaced  </p>") == "spaced");
}

- (void)testDomainExtraction {
    XCTAssertTrue(hn::domainFromURL("https://www.Example.com/path?q=1") == "example.com");
    XCTAssertTrue(hn::domainFromURL("http://sub.example.co.uk:8080/x") == "sub.example.co.uk");
    XCTAssertTrue(hn::domainFromURL("example.com") == "example.com");
    XCTAssertTrue(hn::domainFromURL("not a url").empty());
    XCTAssertTrue(hn::domainFromURL("ftp://example.com").empty());
    XCTAssertTrue(hn::domainFromURL("").empty());
}

- (void)testRelativeTime {
    XCTAssertTrue(hn::timeAgoFromSeconds(30) == "30s ago");
    XCTAssertTrue(hn::timeAgoFromSeconds(90) == "1m ago");
    XCTAssertTrue(hn::timeAgoFromSeconds(7200) == "2h ago");
    XCTAssertTrue(hn::timeAgoFromSeconds(172800) == "2d ago");
    XCTAssertTrue(hn::timeAgoFromUnix(0) == "unknown");
}

- (void)testFeedPaths {
    XCTAssertTrue(std::string(hn::feedPath(hn::Feed::Top)) == "topstories.json");
    XCTAssertTrue(std::string(hn::feedPath(hn::Feed::Jobs)) == "jobstories.json");
    XCTAssertTrue(std::string(hn::feedName(hn::Feed::Ask)) == "Ask");
    XCTAssertTrue(hn::feedFromInt(5) == hn::Feed::Jobs);
    XCTAssertTrue(hn::feedFromInt(99) == hn::Feed::Top);
}

#pragma mark - Cache policy

- (void)testCacheFreshnessBoundaries {
    using hn::CachePolicy;
    XCTAssertTrue(CachePolicy::freshnessForAge(0) == CachePolicy::Freshness::Fresh);
    XCTAssertTrue(CachePolicy::freshnessForAge(299) == CachePolicy::Freshness::Fresh);
    XCTAssertTrue(CachePolicy::freshnessForAge(300) == CachePolicy::Freshness::Stale);
    XCTAssertTrue(CachePolicy::freshnessForAge(1799) == CachePolicy::Freshness::Stale);
    XCTAssertTrue(CachePolicy::freshnessForAge(1800) == CachePolicy::Freshness::Expired);
    XCTAssertTrue(CachePolicy::freshnessForAge(86399) == CachePolicy::Freshness::Expired);
    XCTAssertTrue(CachePolicy::freshnessForAge(86400) == CachePolicy::Freshness::Empty);
    XCTAssertTrue(CachePolicy::freshnessForFetchedAt(0, 1000) == CachePolicy::Freshness::Empty);
    XCTAssertTrue(CachePolicy::freshnessForFetchedAt(900, 1000) == CachePolicy::Freshness::Fresh);
}

#pragma mark - Comment tree

- (void)testCommentTreeUsesRootOrderingAndDepth {
    std::vector<hn::Comment> comments(3);
    comments[0].id = 1;
    comments[0].kids = {2};
    comments[1].id = 2;
    comments[1].kids = {3};
    comments[2].id = 3;

    const auto roots = hn::buildCommentTree(comments, {1});
    XCTAssertEqual(roots.size(), static_cast<size_t>(1));
    XCTAssertEqual(roots[0].comment.id, 1);
    XCTAssertEqual(roots[0].depth, 0);
    XCTAssertEqual(roots[0].children.size(), static_cast<size_t>(1));
    XCTAssertEqual(roots[0].children[0].comment.id, 2);
    XCTAssertEqual(roots[0].children[0].depth, 1);
    XCTAssertEqual(roots[0].children[0].children[0].comment.id, 3);
    XCTAssertEqual(hn::countCommentNodes(roots), 3);
}

- (void)testCommentTreeBreaksCycles {
    std::vector<hn::Comment> comments(2);
    comments[0].id = 1;
    comments[0].kids = {2};
    comments[1].id = 2;
    comments[1].kids = {1};

    const auto roots = hn::buildCommentTree(comments, {1});
    XCTAssertEqual(hn::countCommentNodes(roots), 2);
}

- (void)testCommentTreeFallsBackWhenRootsMissing {
    std::vector<hn::Comment> comments(2);
    comments[0].id = 10;
    comments[1].id = 11;
    comments[0].kids = {11};

    const auto roots = hn::buildCommentTree(comments, {99});
    XCTAssertEqual(roots.size(), static_cast<size_t>(1));
    XCTAssertEqual(roots[0].comment.id, 10);
}

#pragma mark - Search index

- (void)testSearchIndexRanksAndRemoves {
    hn::SearchIndex index;
    hn::Story rust;
    rust.id = 1;
    rust.title = "Rust compiler reaches 1.0";
    rust.author = "alice";
    rust.domain = "rust-lang.org";
    rust.text = "Memory safety without garbage collection";
    rust.score = 100;
    rust.createdAt = 1000;

    hn::Story swift;
    swift.id = 2;
    swift.title = "Swift concurrency explained";
    swift.author = "bob";
    swift.domain = "swift.org";
    swift.score = 50;
    swift.createdAt = 2000;

    index.upsert(rust);
    index.upsert(swift);
    XCTAssertEqual(index.size(), 2);

    auto results = index.search("rust");
    XCTAssertFalse(results.empty());
    XCTAssertEqual(results.front(), 1);

    results = index.search("alice");
    XCTAssertEqual(results.size(), static_cast<size_t>(1));
    XCTAssertEqual(results.front(), 1);

    results = index.search("memory safety");
    XCTAssertEqual(results.size(), static_cast<size_t>(1));

    index.remove(1);
    XCTAssertEqual(index.size(), 1);
    XCTAssertTrue(index.search("rust").empty());
    XCTAssertEqual(index.search("swift").front(), 2);
}

#pragma mark - Store

- (void)testStorePersistsStoriesCommentsAndSaved {
    hn::Store store;
    std::string error;
    XCTAssertTrue(store.open(":memory:", &error));

    hn::Story story;
    story.id = 42;
    story.type = "story";
    story.title = "A cached story";
    story.author = "carol";
    story.url = "https://example.com/post";
    story.text = "<p>Body</p>";
    story.createdAt = 1234;
    story.score = 17;
    story.commentCount = 2;
    story.kids = {7, 8};
    story.fetchedAt = hn::nowUnix();
    XCTAssertTrue(store.upsertStory(story));

    const auto loaded = store.story(42);
    XCTAssertTrue(loaded.has_value());
    XCTAssertTrue(loaded->title == story.title);
    XCTAssertEqual(loaded->kids.size(), static_cast<size_t>(2));
    XCTAssertTrue(loaded->domain == "example.com");

    hn::FeedMeta meta;
    meta.feed = hn::Feed::Best;
    meta.fetchedAt = 555;
    meta.ids = {42, 43};
    XCTAssertTrue(store.setFeedMeta(meta));
    const auto loadedMeta = store.feedMeta(hn::Feed::Best);
    XCTAssertTrue(loadedMeta.has_value());
    XCTAssertTrue(loadedMeta->ids == meta.ids);

    std::vector<hn::Comment> comments(2);
    comments[0].id = 7;
    comments[0].storyId = 42;
    comments[0].author = "dave";
    comments[0].kids = {8};
    comments[1].id = 8;
    comments[1].storyId = 42;
    comments[1].parentId = 7;
    XCTAssertTrue(store.upsertComments(comments));
    XCTAssertEqual(store.comments(42).size(), static_cast<size_t>(2));

    XCTAssertTrue(store.setSaved(42, true, &story));
    XCTAssertTrue(store.savedStory(42).has_value());
    XCTAssertEqual(store.countSaved(), 1);
    XCTAssertTrue(store.savedIds().count(42) == 1);

    XCTAssertTrue(store.clear(true));
    XCTAssertTrue(store.story(42).has_value());
    XCTAssertEqual(store.countSaved(), 1);
    XCTAssertEqual(store.comments(42).size(), static_cast<size_t>(2));

    XCTAssertTrue(store.clear(false));
    XCTAssertFalse(store.story(42).has_value());
    XCTAssertEqual(store.countStories(), 0);
    XCTAssertEqual(store.countComments(), 0);
    XCTAssertEqual(store.countSaved(), 0);
}

#pragma mark - Dispatcher

- (void)testDispatcherRunsTasksAndTimersInOrder {
    auto dispatcher = std::make_shared<hn::Dispatcher>();
    dispatcher->start();

    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    dispatcher->post([order] {
        [order addObject:@1];
    });
    dispatcher->postDelayed(10, [order, semaphore] {
        [order addObject:@2];
        dispatch_semaphore_signal(semaphore);
    });

    const long timedOut = dispatch_semaphore_wait(
        semaphore, dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(2 * NSEC_PER_SEC)));
    XCTAssertEqual(timedOut, 0);
    XCTAssertEqual(order.count, static_cast<NSUInteger>(2));
    XCTAssertEqualObjects(order[0], @1);
    XCTAssertEqualObjects(order[1], @2);

    dispatcher->stop();
    XCTAssertFalse(dispatcher->isRunning());
}

@end
