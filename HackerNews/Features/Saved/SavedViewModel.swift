import Foundation
import Combine

@MainActor
final class SavedViewModel: ObservableObject {
    @Published private(set) var savedStories: [SavedStory] = []
    @Published var searchText = ""

    private let client: EngineClient
    private var cancellables = Set<AnyCancellable>()

    init(client: EngineClient = .shared) {
        self.client = client
        client.$savedStories
            .sink { [weak self] stories in
                self?.savedStories = stories
            }
            .store(in: &cancellables)
        savedStories = client.saved()
    }

    func refresh() {
        savedStories = client.saved()
    }

    func unsave(_ saved: SavedStory) {
        client.setSaved(false, storyID: saved.storyID)
        HapticsManager.lightImpact()
        SoundManager.playUnsaveSound()
    }

    var filtered: [SavedStory] {
        guard !searchText.isEmpty else { return savedStories }
        let lower = searchText.lowercased()
        return savedStories.filter { saved in
            saved.title?.lowercased().contains(lower) == true ||
            saved.author?.lowercased().contains(lower) == true ||
            String(saved.storyID).contains(lower)
        }
    }
}
