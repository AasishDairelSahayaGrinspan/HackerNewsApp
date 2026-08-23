import Foundation
import SwiftData

@MainActor
final class SavedViewModel: ObservableObject {
    @Published var savedStories: [SavedStory] = []
    @Published var cachedStories: [Int: CachedStory] = [:]
    @Published var searchText = ""

    private let persistence: PersistenceController

    init(persistence: PersistenceController? = nil) {
        self.persistence = persistence ?? PersistenceController.shared
        refresh()
    }

    func refresh() {
        savedStories = persistence.fetchSavedStories()
        var map: [Int: CachedStory] = [:]
        for s in savedStories {
            if let cached = persistence.fetchCachedStory(id: s.storyID) {
                map[s.storyID] = cached
            }
        }
        cachedStories = map
    }

    func unsave(_ saved: SavedStory) {
        persistence.unsaveStory(id: saved.storyID)
        HapticsManager.lightImpact()
        SoundManager.playUnsaveSound()
        refresh()
    }

    var filtered: [SavedStory] {
        guard !searchText.isEmpty else { return savedStories }
        let lower = searchText.lowercased()
        return savedStories.filter { s in
            s.title?.lowercased().contains(lower) == true ||
            s.author?.lowercased().contains(lower) == true ||
            String(s.storyID).contains(lower)
        }
    }
}
