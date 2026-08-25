public import Foundation

public import StoryArcCore

public struct ReaderPreferences {
    private let defaults: UserDefaults
    private let fitKey = "app.storyarc.pageFit"
    private let themesKey = "app.storyarc.themes"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func pageFit() -> PageFit {
        PageFit(rawValue: defaults.string(forKey: fitKey) ?? "") ?? .screen
    }

    public func save(_ fit: PageFit) {
        defaults.set(fit.rawValue, forKey: fitKey)
    }

    /// Every reading theme the reader has chosen, per shelf and per scope.
    ///
    /// One blob rather than a key per shelf: the whole point of `ShelfMemory` is that
    /// resolution walks from shelf to scope to built-in default, and a store that
    /// scattered the entries across `UserDefaults` keys would have to reimplement
    /// that walk. Unreadable stored data reads as no data — a theme is a preference,
    /// and losing one is worth far less than refusing to open the book.
    public func themes() -> ShelfMemory {
        guard let data = defaults.data(forKey: themesKey),
              let memory = try? JSONDecoder().decode(ShelfMemory.self, from: data)
        else { return ShelfMemory() }
        return memory
    }

    public func save(_ memory: ShelfMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: themesKey)
    }
}
