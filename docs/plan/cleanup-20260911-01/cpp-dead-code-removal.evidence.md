# Evidence log - cpp-dead-code-removal (cleanup-20260911-01)

Task: cpp-dead-code-removal, wave 1
Date (UTC): 2026-09-11
Owner files: HackerNews/Core/CppCore/include/HNCppEngine.hpp, HackerNews/Core/CppCore/src/HNCppEngine.cpp
Rule: keep-on-any-live-ref; delete only on zero live refs outside own definition block.

## Pre-delete greps (run BEFORE edits)

### 1) Repo-wide word grep per symbol (includes docs/README prose hits)
Commands:
  for s in search evictionPlan EvictionResult mergeStories buildCommentTree buildCommentTreeFlat flattenTree countNodes; do rg -n --no-heading "\b${s}\b" .; done

Results:
- search: hits ONLY in (a) owned files HNCppEngine.hpp:50-51 decl + HNCppEngine.cpp:247 def, (b) unrelated Swift-local StoryRepository.swift:12,195 func search, StoryRepositoryTests.swift:96,100 sut.search, SearchView.swift:63 repo.search, (c) prose docs README.md:34,105,106,116 + docs/plan/cleanup-20260911-01/plan.yaml scoping text. Zero HNCppEngine::search callers. Swift search hits are NOT C++ refs. Verdict: REMOVE C++ search.
- evictionPlan: hits ONLY in owned files HNCppEngine.hpp:61 decl + HNCppEngine.cpp:279 def, plus README.md:34 prose + plan.yaml scoping text. Zero callers in HackerNews/, HackerNewsTests/, Bridge, CppEngine.swift. Verdict: REMOVE.
- EvictionResult: hits ONLY in owned files HNCppEngine.hpp:57 struct def + HNCppEngine.hpp:61 return type + HNCppEngine.cpp:279 qualified return + HNCppEngine.cpp:287 local var, plus plan.yaml ownership text. Zero refs in Swift/bridge/tests. Exclusivity proof: every code ref is inside evictionPlan decl/def or the struct itself; all die together. Verdict: REMOVE with evictionPlan (exclusivity proven).
- mergeStories: hits ONLY in owned files HNCppEngine.hpp:27 decl + HNCppEngine.cpp:102 def, plus plan.yaml scoping text. Zero callers elsewhere. Verdict: REMOVE.
- buildCommentTree: hits ONLY in owned files HNCppEngine.hpp:34 decl + HNCppEngine.cpp:124 def + HNCppEngine.cpp:171 internal call from buildCommentTreeFlat (same dead tree block). Zero external callers. Verdict: REMOVE (internal ref dies with block).
- buildCommentTreeFlat: hits ONLY in owned files HNCppEngine.hpp:38 decl + HNCppEngine.cpp:162 def, plus plan.yaml scoping text. Zero callers elsewhere. Verdict: REMOVE.
- flattenTree: hits ONLY in owned files HNCppEngine.hpp:41 decl + HNCppEngine.cpp:174 def + HNCppEngine.cpp:178 recursive self-call. Zero external callers. Verdict: REMOVE.
- countNodes: hits ONLY in owned files HNCppEngine.hpp:42 decl + HNCppEngine.cpp:182 def + HNCppEngine.cpp:184 recursive self-call, plus plan.yaml scoping text. Zero callers elsewhere. Verdict: REMOVE.

### 2) Qualified refs in product/test code (excludes docs/README prose)
Command:
  rg -n "HNCppEngine::(search|evictionPlan|mergeStories|buildCommentTree|buildCommentTreeFlat|flattenTree|countNodes)|EvictionResult" HackerNews HackerNewsTests
Result: only the 9 owned-file lines listed above (hpp:57,61; cpp:102,124,162,171-internal,174,178-self,182,184-self,247,279,287). No caller outside HNCppEngine.hpp/.cpp. Exit detail: matches found only in owned files.

### 3) Bridge + facade check (must be zero)
Command:
  rg -n "\b(search|evictionPlan|EvictionResult|mergeStories|buildCommentTree|buildCommentTreeFlat|flattenTree|countNodes)\b" HackerNews/Core/CppCore/Bridge/HNCppBridge.h HackerNews/Core/CppCore/Bridge/HNCppBridge.mm HackerNews/Core/CppCore/CppEngine.swift
Result: zero hits (exit 1). Bridge calls only feedEndpoint/feedFromString/feedIcon/feedDescription, deduplicateIDs, chunkIDs, stripHTML, timeAgoFromUnix, extractDomain, storyURL, itemEndpoint. Facade exposes only endpoint/isFresh/freshness/deduplicate/chunk/stripHTML/domain/timeAgo/storyURL/version/stats. Confirmed.

### 4) Tests check
Command:
  rg -n "\b(evictionPlan|EvictionResult|mergeStories|buildCommentTree|buildCommentTreeFlat|flattenTree|countNodes)\b" HackerNewsTests
Result: zero hits (exit 1). Swift "search" hits in tests are StoryRepository sut.search, unrelated to C++.

## Changes made
- HNCppEngine.hpp: removed mergeStories decl, buildCommentTree/buildCommentTreeFlat/flattenTree/countNodes decls, search decl, EvictionResult struct + evictionPlan decl. (39 lines removed)
- HNCppEngine.cpp: removed mergeStories def, comment-tree block defs, search def, evictionPlan def. (144 lines removed)
- Kept (per default-keep, untouched): feedEndpoint, feedRawValue, feedFromString, feedIcon, feedDescription, allFeeds, deduplicateIDs, chunkIDs, stripHTML, htmlToPlainText, timeAgoFromUnix, timeAgoFromInterval, extractDomain, storyURL, itemEndpoint, all includes, CachePolicyCpp, HNTypes.hpp.
- Kept symbols log: none of the 8 candidates kept; zero keep-paths (zero live refs for all). EvictionResult removed WITH exclusivity proof above.
- Not modified (per constraints): HNCppBridge.h/.mm, CppEngine.swift, HNTypes.hpp, CachePolicyCpp, FeedType.swift, HomeView*, HackerNewsApp.swift, LaunchController.swift.

## Post-delete verification
Commands:
  rg -n "HNCppEngine::(search|evictionPlan|mergeStories|buildCommentTree|buildCommentTreeFlat|flattenTree|countNodes)|EvictionResult" HackerNews HackerNewsTests  -> zero hits (exit 1)
  rg -n "\b(search|evictionPlan|EvictionResult|mergeStories|buildCommentTree|buildCommentTreeFlat|flattenTree|countNodes)\b" HackerNews/Core/CppCore/include/HNCppEngine.hpp HackerNews/Core/CppCore/src/HNCppEngine.cpp -> zero hits (exit 1)
- No broken refs: Bridge/facade/tests never referenced removed symbols, so no dangling refs possible. Full xcodebuild test is wave-2 locked step, not run here.
- Blast radius: single module (HNCppEngine decl/def only); no public Bridge/Swift contract changed.
- Note: repo has unrelated dirty files from parallel work (HackerNews.xcodeproj/project.pbxproj, HackerNews/API/HackerNewsAPI.swift, HackerNews/Features/Home/HomeView.swift). Not touched by this task; owned diff is hpp/cpp only.
