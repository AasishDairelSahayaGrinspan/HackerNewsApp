# Evidence log - home-feed-ui-and-launch-cleanup (cleanup-20260911-01)

Task: home-feed-ui-and-launch-cleanup, wave 1
Date (UTC): 2026-09-11
Owner files: HackerNews/Features/Home/HomeView.swift, HackerNews/Features/Home/HomeViewModel.swift, HackerNews/Features/Launch/LaunchController.swift, HackerNews/App/HackerNewsApp.swift only plus this log
Rule: writer pre-check before strip; keep FeedType.top plumbing, do not delete multi-feed backend.

## Pre-check greps (run BEFORE edits)

### 1) selectedFeed writers/readers
Command:
  rg -n "selectedFeed|FeedType\.allCases" --glob "*.swift" .
Result:
- HomeView.swift:24 ForEach(FeedType.allCases), :27 viewModel.selectedFeed = feed, :45 onChange(of: viewModel.selectedFeed), :58 ForEach(FeedType.allCases), :61 viewModel.selectedFeed = feed, :65/:68/:69/:72 reads for styling/selection
- HomeViewModel.swift:9 @Published var selectedFeed = .top (declaration, default .top), :40/:57/:78 reads for repository calls
- Zero writers outside Home (no other file sets selectedFeed). Verdict: safe to strip picker/Menu/onChange and pin to .top.

### 2) FeedType.allCases scope
Command:
  rg -n "FeedType" --glob "*.swift" .
Result:
- FeedType.allCases hits ONLY in HomeView.swift:24 (Menu) and :58 (pill picker). No other file uses allCases.
- Backend plumbing kept untouched per constraints: FeedType.swift enum, StoryRepository stories(for:/refresh(feed: + loadedIDs dict, HackerNewsAPI fetchStoryIDs(for: + storyIDs dict, PersistenceController fetchStories/updateCacheMetadata/lastFetched(for:, PersistenceModels feedTypeRaw mapping, CppEngine endpoint(for:. Verdict: REMOVE UI enumeration only, keep backend.

### 3) Launch dead hooks
Command:
  rg -n "isWarm|markBackgrounded|markForegrounded|scenePhase|shouldShowAnimation|launchController" --glob "*.swift" .
Result:
- LaunchController.swift: isWarm decl :10, writes :21 only, zero reads elsewhere. markBackgrounded/markForegrounded decls :28-:29, callers only HackerNewsApp.swift:53/:56 inside scenePhase onChange.
- HackerNewsApp.swift: scenePhase decl :10 used only by :51 onChange block for dead no-ops. Splash overlay :43 shouldShowAnimation/finished + complete() :45 is live.
- Verdict: REMOVE isWarm + both no-ops + scenePhase property + onChange block; KEEP shouldShowAnimation/finished/complete/splash overlay.

## Changes made
- HomeView.swift: removed feedPicker ref from VStack, removed toolbar Menu (FeedType.allCases), removed onChange(of: selectedFeed) + stale coalesce comment, removed feedPicker private var block, removed dead @State searchText (zero refs in Home). Net -50 lines. No FeedType.allCases, no feedPicker, no Menu remain.
- HomeViewModel.swift: @Published var selectedFeed -> let selectedFeed = .top (pinned, read-only); collapsed redundant if/else loadState = .loading branch; updated stale "feed switches" comment to "Coalesce overlapping loads". All 3 repository calls now use pinned .top.
- LaunchController.swift: removed @Published isWarm + assignments, removed markBackgrounded()/markForegrounded() no-ops. Kept once-ever init + complete() + shouldShowAnimation/finished.
- HackerNewsApp.swift: removed @Environment scenePhase + onChange(scenePhase) dead hook block. Kept splash ZStack overlay, deep-link onOpenURL, cache eviction task, RootTabView/tabs untouched.
- Not modified: FeedType.swift, StoryRepository, HackerNewsAPI, PersistenceController, CppCore files, other tabs, deep-link post/routing.

## Post-edit verification
Commands:
  rg -n "allCases|feedPicker|markBackgrounded|markForegrounded|isWarm|scenePhase" --glob "*.swift" . -> zero hits
  rg -n "selectedFeed" --glob "*.swift" . -> only HomeViewModel.swift:9 let decl + :34/:51/:72 reads (no setters)
- No broken refs: HomeView no longer references selectedFeed/allCases; tests (ViewModelTests) use default init + loadInitial with .top mock, no setter/isWarm refs.
- Blast radius: Home UI + HomeVM constant + Launch no-ops only; module contracts unchanged (FeedType enum, repository signatures intact); deep-link/tabs unchanged.
- Note: repo has unrelated dirty files from parallel work (HackerNews.xcodeproj/project.pbxproj, HackerNews/API/HackerNewsAPI.swift, HNCppEngine.hpp/.cpp). Not touched by this task; owned diff is the 4 files above only.
