# Hacker News — Native iOS app with a C++ engine

A native Hacker News client for iPhone and iPad. SwiftUI renders the interface;
a C++20 engine owns networking, persistence, caching, comment traversal, search,
state and telemetry. Swift no longer contains a repository, API client,
SwiftData model container or cache policy.

The engine is structured like a market-data/trading core: a single event
dispatcher owns mutable state, network results are posted back as events, and
the UI receives immutable snapshots tagged with a monotonic revision.

## Requirements

* Xcode 26.3+ (iOS 26 SDK)
* iOS 17.0+ deployment target
* No third-party dependencies
* `xcodegen` for project regeneration

## Architecture

```
HackerNews/
├── App/                       SwiftUI app entry, deep links, tab shell
├── Core/Engine/
│   ├── include/hn/            Public C++ engine headers
│   │   ├── Types.hpp          Items, stories, comments, snapshots, telemetry
│   │   ├── Feed.hpp           6 feed identifiers
│   │   ├── Engine.hpp         Engine facade and command API
│   │   ├── Dispatcher.hpp     Single command loop + delayed timer queue
│   │   ├── ApiClient.hpp      Coalescing, retries, bounded request batches
│   │   ├── Store.hpp          SQLite write-behind persistence
│   │   ├── SearchIndex.hpp    In-memory token index + substring fallback
│   │   ├── Tree.hpp           Comment tree builder with cycle guards
│   │   ├── Json.hpp           Dependency-free JSON parser
│   │   ├── Text.hpp           HTML, domains, relative time, feed paths
│   │   ├── CachePolicy.hpp    5m fresh / 30m stale / 24h max
│   │   └── Transport.hpp      Platform HTTP boundary
│   ├── src/                   Engine implementation
│   ├── platform/
│   │   └── AppleTransport.mm  NSURLSession isolation (ObjC++)
│   ├── Bridge/
│   │   ├── HNEngine.h         Typed Objective-C facade + listener protocol
│   │   └── HNEngine.mm        ObjC++ conversion and main-queue delivery
│   ├── EngineClient.swift     ObservableObject adapter over the bridge
│   └── EngineModels.swift     Swift presentation models and snapshot mapping
├── Features/                  Home, StoryDetail, Comments, Saved, Search, Settings
├── Shared/                    Components and small presentation extensions
└── Domain/                    FeedType bridge mapping
```

### Event-driven core

`hn::Engine` creates:

* one **worker dispatcher** thread that executes every command,
* one **timer** thread for retries, heartbeats and delayed work,
* an `ApiClient` that posts network completions back onto the dispatcher.

All mutable engine state — feed pages, story snapshots, comment BFS state,
saved IDs, metrics and status — is touched only on the dispatcher thread.
Network callbacks never mutate state directly.

### Snapshot + revision stream

Every UI update is an immutable snapshot with a `revision`:

* `FeedSnapshot` — phase, ordered stories, last sync, offline/stale flags, error
* `StorySnapshot` — story detail phase and payload
* `CommentsSnapshot` — nested comment roots, loading/complete flags, totals
* `SavedSnapshot` — saved rows
* `Status` — cache counts, database size, uptime, metrics

The bridge converts these to Objective-C models and delivers listener callbacks
on the main queue. `EngineClient` mirrors them into Combine publishers; view
models map them into Swift structs and forward user intents as commands.

### Networking

`AppleTransport.mm` is the only Apple networking code. It performs an
`NSURLSession` request and reports status, body, error class and latency. All
retry, in-flight request coalescing, ordering, batching and timeout policy live
in C++:

* feed IDs: `topstories.json`, `newstories.json`, `beststories.json`,
  `askstories.json`, `showstories.json`, `jobstories.json`
* items: `item/{id}.json`, `maxitem.json`
* base URL: `https://hacker-news.firebaseio.com/v0/`
* retries: two attempts with 350ms / 800ms backoff for transient failures
* feed batch concurrency: 8
* comment batch concurrency: 12
* duplicate item requests are merged through a waiter list

### Persistence and cache policy

`Store` uses the SQLite C API directly with WAL mode:

* `stories` — decoded stories keyed by HN item ID
* `comments` — flat comment rows keyed by comment ID
* `saved` — user-owned saved rows (never evicted)
* `feed_meta` — ordered feed ID lists and fetch timestamps

SQLite is the write-behind journal. The engine updates the in-memory book,
emits a snapshot, and persists in the same command turn. The cache policy is a
single C++ source of truth:

* fresh: `< 5 minutes`
* stale: `< 30 minutes`
* expired: `< 24 hours`
* eviction keeps saved stories, feed head (200 IDs) and 3 days of data

Saved stories survive `Clear Cache (Keep Saved)`. `Clear Everything` removes
stories, comments, feed metadata and saved rows.

### Comments

The comment loader is a level-by-level BFS, not recursive network traversal:

* root IDs come from the story's `kids`
* 25 IDs per batch, 12 concurrent requests
* hard cap 500 comments
* maximum depth 6 levels of replies
* at most 30 branches per node
* progressive snapshots stream into the UI as each level completes
* the tree builder breaks cycles and depth overflows deterministically

### Search

Search is local and network-free, because the official HN API has no full-text
search. `SearchIndex` maintains:

* a token posting list over title, author, domain and story text
* prefix matching for partial words
* substring/field weighting fallback
* deterministic ordering by relevance, score, creation time and ID

The index is rebuilt from SQLite on launch and updated as stories are fetched.

## How to run

```bash
xcodegen generate
open HackerNews.xcodeproj
# Select a simulator or your connected iPhone.
# Signing: enable automatic signing and choose the team that matches your
# local Apple Development profile.
# Bundle ID: com.aasishdarrel.hacknews (change if it is taken).
# Cmd+R
```

Command line:

```bash
# Simulator
xcodebuild -project HackerNews.xcodeproj -scheme HackerNews \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' build

# Connected device (replace the UDID and team with your own)
xcodebuild -project HackerNews.xcodeproj -scheme HackerNews \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -allowProvisioningUpdates build

xcrun devicectl device install app --device <DEVICE_UDID> \
  <DerivedData>/Build/Products/Debug-iphoneos/HackerNews.app
xcrun devicectl device process launch --device <DEVICE_UDID> \
  com.aasishdarrel.hacknews
```

## Tests

```bash
xcodebuild test -project HackerNews.xcodeproj -scheme HackerNews \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
```

19 tests, no live network:

* `HNCoreTests.mm` — C++ XCTest covering JSON, HTML/entities, domains,
  relative time, feed paths, cache freshness boundaries, comment-tree ordering
  and cycle breaking, search indexing, SQLite stories/comments/saved/clear,
  and dispatcher ordering/timers.
* `HNEngineBridgeTests.swift` — Objective-C++ bridge and engine lifecycle:
  start/status/version, save/unsave round trips, local search start state,
  clear-cache behavior, and story snapshot delivery.

The same suite runs on a connected iPhone with:

```bash
xcodebuild test -project HackerNews.xcodeproj -scheme HackerNews \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -allowProvisioningUpdates
```

## Features

* Six feeds: Top, New, Best, Ask, Show, Jobs
* Offline-first feed with cached stories and an offline banner
* Infinite scroll and pull-to-refresh
* Saved stories with swipe-to-unsave and local filtering
* Local search over cached stories
* Story detail with article browser, share sheet, HTML body rendering
* Nested comments with collapse/expand and progressive streaming
* Deep link: `hnreader://story/123`
* Haptics and system sounds, respecting user settings
* Appearance (system/light/dark)
* Settings engine diagnostics: cached rows, database size, requests, retries,
  cache hit rate, latency, snapshots and uptime
* X-style launch animation
* Dynamic Type, VoiceOver labels, Reduce Motion support

## Known limitations

* HN has no full-text search API; search covers only locally cached stories.
* Comment loading intentionally caps at 500 nodes, depth 6 and 30 branches per
  node to avoid pathological threads; truncated tails are not paginated.
* External article HTML is not mirrored; articles open in Safari.
* Cache eviction is opportunistic on launch/background, not scheduled with
  `BGTaskScheduler`.
