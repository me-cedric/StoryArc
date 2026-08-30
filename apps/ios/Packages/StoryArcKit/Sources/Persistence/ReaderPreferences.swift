public import Foundation

public import StoryArcCore

public struct ReaderPreferences {
    private let defaults: UserDefaults
    /// The one fit the whole library used to share. Read once, folded into the
    /// fixed-layout default, and removed. See ``themes()``.
    private let legacyFitKey = "app.storyarc.pageFit"
    private let themesKey = "app.storyarc.themes"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every reading theme the reader has chosen, per shelf and per scope.
    ///
    /// One blob rather than a key per shelf: the whole point of `ShelfMemory` is that
    /// resolution walks from shelf to scope to built-in default, and a store that
    /// scattered the entries across `UserDefaults` keys would have to reimplement
    /// that walk. Unreadable stored data reads as no data — a theme is a preference,
    /// and losing one is worth far less than refusing to open the book.
    ///
    /// It is also where the page fit is picked up from where it used to live. The fit
    /// was one value for the whole library before `comic-reader`'s "persists per series"
    /// was honoured, and a reader who had chosen fit-to-width would otherwise find every
    /// comic they own back at fit-to-screen on the day they updated. So the old value
    /// becomes the fixed-layout *default*: every shelf that has not been told otherwise
    /// inherits it, which is exactly what "global" meant, and a shelf they set later
    /// keeps its own. The old key is removed as it is folded in, so this happens once.
    public func themes() -> ShelfMemory {
        let memory = storedThemes()
        guard let raw = defaults.string(forKey: legacyFitKey),
              let fit = PageFit(rawValue: raw)
        else { return memory }
        let migrated = memory.settingDefault(
            memory.default(for: .fixedLayout).settingFit(fit),
            for: .fixedLayout
        )
        defaults.removeObject(forKey: legacyFitKey)
        save(migrated)
        return migrated
    }

    public func save(_ memory: ShelfMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: themesKey)
    }

    private func storedThemes() -> ShelfMemory {
        guard let data = defaults.data(forKey: themesKey),
              let memory = try? JSONDecoder().decode(ShelfMemory.self, from: data)
        else { return ShelfMemory() }
        return memory
    }
}
