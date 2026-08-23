# Hacker News - Production iOS App with C++ Core

Production-grade native Hacker News client for iPhone. SwiftUI + SwiftData + **C++20 Core Engine** (hybrid). Feels like a serious App Store product, not a demo.

## Overview

Reads the official [Hacker News Firebase API](https://github.com/HackerNews/API) (`https://hacker-news.firebaseio.com/v0/`). No scraper, no auth, no third-party networking. Offline-first, cached, saved, searchable, accessible.

## Requirements

* Xcode 26.3+ (Swift 6.2.4, iOS SDK 26.2)
* iOS 17.0+ deployment target (SwiftData)
* iPhone + iPad (portrait + landscape, Dynamic Type, VoiceOver, Reduce Motion, Dark Mode)

## Architecture

```
App (SwiftUI App)
 ├─ Core
 │   ├─ CppCore (C++20) — HNCppEngine, CachePolicyCpp, HNTypes, Bridge
 │   ├─ Networking (URLSession, async/await, retry, timeout)
 │   ├─ Persistence (SwiftData: CachedStory, CachedComment, SavedStory, CacheMetadata)
 │   ├─ Caching (CachePolicy fresh/stale/expired)
 │   ├─ Haptics/Audio (UIImpact, SystemSound)
 │   └─ Logging (os.Logger)
 ├─ API (HackerNewsAPI actor, DTOs, Endpoint)
 ├─ Data (StoryRepository, CommentRepository - offline-first, BFS, chunked)
 ├─ Domain (FeedType)
 └─ Features (Home, StoryDetail, Comments, Saved, Search, Settings, Browser)
```

**C++ Core Engine** (`HackerNews/Core/CppCore/`):
* `include/HNTypes.hpp` - `HNItem`, `CommentNode`, `FeedType`
* `include/HNCppEngine.hpp` / `src/HNCppEngine.cpp` - deduplication (`unordered_set`), chunking (`chunkIDs`), merge, comment tree BFS, `stripHTML`, `timeAgo`, `domain`, `search`, `evictionPlan`
* `include/CachePolicyCpp.hpp` / `src/CachePolicyCpp.cpp` - single source of truth for 5m/30m/24h
* `Bridge/HNCppBridge.h/.mm` - Objective-C++ bridge to Swift
* `CppEngine.swift` - Swift facade (`HNCppBridge.endpoint(forFeed:)`, `deduplicate`, `chunk`, `stripHTML`, etc.)

SwiftUI is `@MainActor`, persistence is `PersistenceController` actor-isolated, networking is `URLSession` + `async/await` with bounded concurrency (`AsyncSemaphore`, `httpMaximumConnectionsPerHost=12`). Swift calls C++ for hot paths.

## API Architecture

```
https://hacker-news.firebaseio.com/v0/
  /topstories.json, /newstories.json, /beststories.json, /askstories.json, /showstories.json, /jobstories.json
  /item/{id}.json  (story, comment, job, poll, pollopt)
  /maxitem.json
```

* Single `APIClient` (`final class`, `@unchecked Sendable`) with 15s request / 30s resource timeout, `waitsForConnectivity`, retry once on 5xx/timeout.
* `HackerNewsAPI` actor: deduplicates in-flight IDs (`inFlight: [Int: Task]`), chunked `fetchItems(ids:maxConcurrency:)` - 30-ID chunks, `maxConcurrency=12` via C++ `chunkIDs`, preserves input order.
* Decoding: `HNItemDTO` forward-compatible (ignores unknown fields, all optional except `id`).

## Caching & Offline-First

```
Local cache first -> show -> fetch network -> merge -> persist -> update UI
```

* `CachePolicy` / `CachePolicyCpp`: `fresh<5m`, `stale<30m`, `expired<24h`, `empty`.
* `PersistenceController` (SwiftData, in-memory for tests): `CachedStory`, `CachedComment` (`isHnDeleted` not `isDeleted` to avoid `NSManagedObject.isDeleted` clash), `SavedStory`, `CacheMetadata` (ordered `storyIDs` per feed).
* `StoryRepository.stories(for:page:)` - returns cached if fresh, otherwise triggers background `refresh()`. Pagination via `loadedIDs` and `page*pageSize`.
* `CommentRepository` - BFS level-by-level (not depth-first recursion) with C++ chunking (25 per chunk, 12 concurrent), hard cap 500, per-node branching limited to 30, deduped next level. High-volume (>100) streams: first 30 in <1s (`loadCommentsStreaming`), remaining in background, deepens 3->6.
* `Saved` is user-owned, never evicted by `evictExpiredCache(maxFeedItems:200, maxAge:3d)` or `clearAllCache(keepSaved:true)`.

Offline: `ConnectivityMonitor` (`NWPathMonitor`) shows `Offline · Showing cached content`. Pull-to-refresh keeps cached visible.

## Persistence Strategy

SwiftData `ModelContainer` (`isStoredInMemoryOnly` for tests). `fetchStories(for:)` uses `CacheMetadata` order, fallback to `feedTypeRaw` filter. `isSaved` checks `SavedStory`. `clearAllCache` deletes stories/comments/metadata but spares `Saved`.

## How to Run

```bash
xcodegen generate
open HackerNews.xcodeproj
# Select iPhone 17 simulator or your iPhone (Darrel Vengeance's iphone, 00008030-00024C860C60402E)
# Signing: TARGETS > HackerNews > Signing & Capabilities > Team: L8HTG27444 (AasishDairel)
# Bundle ID: com.aasishdarrel.hacknews (change if taken)
# Cmd+R
```

CLI:
```bash
xcodebuild -project HackerNews.xcodeproj -scheme HackerNews -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' build
xcodebuild -project HackerNews.xcodeproj -scheme HackerNews -destination 'platform=iOS,id=00008030-00024C860C60402E' -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008030-00024C860C60402E Build/Products/Debug-iphoneos/HackerNews.app
```

## How to Run Tests

```bash
xcodebuild test -project HackerNews.xcodeproj -scheme HackerNews -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
# 41 tests: HNItemDTO, Persistence, StoryRepository, CommentTests (including high-volume), ViewModel, APIClient
```

Tests use `MockHackerNewsAPI`/`MockAPIClient` (`@unchecked Sendable`), `PersistenceController(inMemory:true)`. No live network.

## Features

* Home feed with 6 feeds (Top/New/Best/Ask/Show/Jobs) via `FeedType`, pull-to-refresh, infinite scroll, skeletons, offline banner (`OfflineBanner`).
* Story row: title, domain (`CppEngine.domain`), score, author, `timeAgo` (C++), comment count, saved state, 44pt targets.
* Story detail: `SFSafariViewController`, share sheet, HTML `text` via `stripHTML`/`hnAttributedString` (C++ fast path), haptics/sound (respect settings).
* Comments: nested `CommentNode` tree, `CommentTreeView` with collapse/expand (haptics, `Reduce Motion` fade), `isHnDeleted`/`isDead` handling, `LazyVStack` flatten, progressive loading footer (“Fetching replies…”).
* Saved: `SavedView`/`SavedViewModel`, swipe to unsave, search, persists across restarts.
* Search: local `StoryRepository.search(query:)` via C++ `HNCppEngine::search` over cached titles/domains/authors.
* Settings: Appearance (system/light/dark), Haptics/Sound toggles (`SettingsStore` `@MainActor`), clear cache (keep saved), About, deep link `hnreader://story/123`.
* A11y: Dynamic Type, VoiceOver labels/hints, semantic colors, materials, SF Symbols, minimal animations with `Reduce Motion`.

## Dependencies

None third-party. `xcodegen` only for project generation. Native: SwiftUI, SwiftData, URLSession, Network, SafariServices, os.Logger, AVFoundation, UIKit haptics.

## Known Limitations

* HN API has no full-text search — search is local cached only.
* External article HTML not mirrored (in-app browser only, URL cached).
* Comment streaming caps at 500 and per-node 30 to avoid 1313-descendant explosion; “Load more” not yet explicit for truncated tails.
* Background fetch is opportunistic (`evictExpiredCache` on launch), not `BGTaskScheduler`.

## Technical Decisions

* C++20 core for hot paths (dedupe, chunk, HTML, freshness) — measurable for 400-node trees, shared via `HNCppBridge` not Swift-C++ interop to keep ObjC bridging simple.
* `isHnDeleted` rename avoids `NSManagedObject.isDeleted` SwiftData clash that caused high-volume deleted comments to persist as `false`.
* BFS not DFS for comments prevents 5s+ sequential depth-first awaits.
* `final class APIClient` not `actor` to fix `non-Sendable T.Type` Swift 6 warning.
* `PersistenceController` `@MainActor` with `nonisolated` inits for testability; `MockHackerNewsAPI` is `@unchecked Sendable` class not actor to allow test mutation.
