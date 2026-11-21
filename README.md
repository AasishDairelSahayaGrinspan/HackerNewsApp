# Hacker News — Native iOS app with a Swift backend

A native Hacker News client for iPhone and iPad. SwiftUI renders the interface;
a Swift backend owns networking, persistence, caching, comment traversal, search,
state and telemetry. Views only subscribe to immutable snapshots and send
intents — they no longer contain repositories, API clients, cache policy or
SwiftData queries.

The backend keeps the market-data/trading-core structure: one owner of mutable
state, commands in, immutable snapshots with a monotonic revision out.

## Requirements

* Xcode 26.3+ (iOS 26 SDK)
* iOS 17.0+ deployment target
* No third-party dependencies
* `xcodegen` for project regeneration

## Architecture

```
HackerNews/
├── App/                       SwiftUI app entry, deep links, tab shell
├── Core/Backend/
│   ├── AppBackend.swift       Backend facade: feeds, stories, comments, saved,
│   │                          search, cache commands and snapshot emission
│   ├── BackendModels.swift    Domain models, snapshots, status and errors
│   ├── HackerNewsAPI.swift    HN wire protocol, item coalescing, batching
│   ├── APIClient.swift        URLSession transport, retries, URL metrics
│   ├── APIError.swift         Error classification and retry policy
│   ├── APIModels.swift        Wire DTOs and request metrics
│   ├── Endpoint.swift         Typed endpoint-to-URL construction
│   ├── PersistenceModels.swift SwiftData models
│   ├── PersistenceController.swift Store lifecycle, queries, eviction
│   ├── CommentTree.swift      Nested tree builder with cycle guards
│   ├── SearchIndex.swift      In-memory token index + substring fallback
│   └── CachePolicy.swift      5m fresh / 30m stale / 24h max
├── Features/                  Home, StoryDetail, Comments, Saved, Search, Settings
├── Shared/                    Components and small presentation extensions
└── Domain/                    FeedType identifiers
```

### Single-owner state

`AppBackend` is `@MainActor` and owns all mutable state: feed pages, story
snapshots, comment BFS state, saved IDs, metrics and status. Async work returns
to the main actor to apply results. Generations guard feed and comment loads, so
a late response from a previous feed or comment request cannot overwrite current
state.

### Snapshot + revision stream

Every UI update is an immutable snapshot with a `revision`:

* `FeedSnapshotModel` — phase, ordered stories, last sync, offline/stale flags, error
* `StorySnapshotModel` — story detail phase and payload
* `CommentsSnapshotModel` — nested comment roots, loading/complete flags, totals
* `SavedStory` rows
* `EngineStatus` — cache counts, database size, uptime, metrics

`AppBackend` publishes snapshots through Combine; view models map them into
Swift structs and forward user intents as backend commands. Pull-to-refresh
waits on a revision change rather than an arbitrary delay.

### Networking

`APIClient` is the only URLSession transport. `HackerNewsAPI` is an actor that
owns the HN protocol:

* feed IDs: `topstories.json`, `newstories.json`, `beststories.json`,
  `askstories.json`, `showstories.json`, `jobstories.json`
* items: `item/{id}.json`, `maxitem.json`
* base URL: `https://hacker-news.firebaseio.com/v0/`
* retries: two attempts with 400ms / 800ms backoff for transient failures
* feed batch concurrency: 8
* comment batch concurrency: 12
* duplicate item requests are merged through an in-flight task map
* bounded `AsyncSemaphore` caps concurrent item requests

### Persistence and cache policy

SwiftData stores:

* `CachedStory` — decoded stories keyed by HN item ID
* `CachedComment` — flat comment rows keyed by comment ID
* `SavedStoryModel` — user-owned saved rows (never evicted)
* `CacheMetadata` — ordered feed ID lists and fetch timestamps

`CachePolicy` is the single source of truth:

* fresh: `< 5 minutes`
* stale: `< 30 minutes`
* expired: `< 24 hours`
* eviction keeps saved stories, feed head (200 IDs) and 3 days of data

Saved stories survive `Clear Cache (Keep Saved)`. `Clear Everything` removes
stories, comments, feed metadata and saved rows. If an older build left an
incompatible SwiftData store, the backend recreates the disposable cache store
instead of silently degrading to memory.

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

The index is rebuilt from SwiftData on launch and updated as stories are fetched.

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

20 tests, no live network:

* `BackendPersistenceTests.swift` — SwiftData story/comment/saved round trips,
  upsert behavior, clear-cache semantics and eviction retention.
* `BackendSearchTreeTests.swift` — comment-tree ordering, parentless roots,
  cycle and depth guards, search ranking/prefix/domain matching, index updates,
  and cache freshness boundaries.
* `BackendLifecycleTests.swift` — backend start, feed load, feed switching,
  save/unsave snapshots, story detail snapshots, cache clearing and local search
  against a mock HN API.

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
* Settings backend diagnostics: cached rows, database size, requests, retries,
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
