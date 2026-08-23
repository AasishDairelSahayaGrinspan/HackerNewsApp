import XCTest
@testable import HackerNews

@MainActor
final class ViewModelTests: XCTestCase {
    func testHomeViewModelLoadStateTransitions() async {
        let persistence = PersistenceController(inMemory: true)
        let mockAPI = MockHackerNewsAPI()
        mockAPI.storyIDs[.top] = [1]
        mockAPI.items[1] = HNItemDTO(id: 1, deleted: nil, type: "story", by: "a", time: Date().timeIntervalSince1970, text: nil, dead: nil, parent: nil, poll: nil, kids: nil, url: nil, score: 10, title: "Test", parts: nil, descendants: 0)
        let repo = StoryRepository(api: mockAPI, persistence: persistence)
        let vm = HomeViewModel(repository: repo)
        XCTAssertEqual(vm.loadState, .idle)
        await vm.loadInitial()
        if case .loaded(let stories) = vm.loadState {
            XCTAssertEqual(stories.count, 1)
        } else {
            XCTFail("Expected loaded")
        }
    }

    func testHomeViewModelEmptyState() async {
        let persistence = PersistenceController(inMemory: true)
        let mockAPI = MockHackerNewsAPI()
        mockAPI.shouldFail = true
        mockAPI.errorToThrow = .networkUnavailable
        let repo = StoryRepository(api: mockAPI, persistence: persistence)
        let vm = HomeViewModel(repository: repo)
        await vm.loadInitial()
        if case .failed(let val, let err) = vm.loadState {
            XCTAssertNil(val)
            XCTAssertEqual(err, .networkUnavailable)
        } else {
            XCTFail("Expected failed")
        }
    }

    func testSearchViewModelFindsResults() {
        let persistence = PersistenceController(inMemory: true)
        let s = CachedStory(id: 1, title: "SwiftUI is great", author: "alice")
        persistence.context.insert(s)
        persistence.save()
        let repo = StoryRepository(persistence: persistence)
        let vm = SearchViewModel(repo: repo)
        vm.query = "swiftui"
        XCTAssertEqual(vm.results.count, 1)
        vm.query = "nothing"
        XCTAssertTrue(vm.results.isEmpty)
    }

    func testSavedViewModelFiltering() {
        let persistence = PersistenceController(inMemory: true)
        let s = CachedStory(id: 10, title: "Hello World")
        persistence.context.insert(s)
        persistence.save()
        persistence.saveStory(s)
        let vm = SavedViewModel(persistence: persistence)
        XCTAssertEqual(vm.savedStories.count, 1)
        vm.searchText = "hello"
        XCTAssertEqual(vm.filtered.count, 1)
        vm.searchText = "xyz"
        XCTAssertTrue(vm.filtered.isEmpty)
    }
}
