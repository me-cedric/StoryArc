public import Foundation

public import StoryArcCore

public struct ReaderPreferences {
    private let defaults: UserDefaults
    /// The one fit the whole library used to share. Read once, folded into the
    /// fixed-layout default, and removed. See ``themes()``.
    private let legacyFitKey = "app.storyarc.pageFit"
    private let themesKey = "app.storyarc.themes"
    private let scrollOffsetsKey = "app.storyarc.scrollOffsets"
    private let themesChangedAtKey = "app.storyarc.themesChangedAt"
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
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

    /// When each theme field last changed, by its filed name. `library-sync` task 3.5.
    public func themesChangedAt() -> [String: Date] {
        guard let data = defaults.data(forKey: themesChangedAtKey),
              let stamps = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return stamps
    }

    /// Writes what the reader changed, with each changed field stamped now.
    public func save(_ memory: ShelfMemory) {
        save(memory, changedAt: themesChangedAt())
    }

    /// Writes themes with their moments, as a sync leaves them. See
    /// ``ChangeStamps/restamped(changed:before:after:now:)``.
    public func save(_ memory: ShelfMemory, changedAt stamps: [String: Date]) {
        let restamped = ChangeStamps.restamped(
            changed: ThemeStamps.changed(from: storedThemes(), to: memory),
            before: themesChangedAt(), after: stamps, now: now()
        )
        restore(memory, changedAt: restamped)
    }

    /// Writes themes and moments exactly as given: the undo of a failed import or sync.
    public func restore(_ memory: ShelfMemory, changedAt stamps: [String: Date]) {
        guard let data = try? JSONEncoder().encode(memory),
              let moments = try? JSONEncoder().encode(stamps)
        else { return }
        defaults.set(data, forKey: themesKey)
        defaults.set(moments, forKey: themesChangedAtKey)
    }

    private func storedThemes() -> ShelfMemory {
        guard let data = defaults.data(forKey: themesKey),
              let memory = try? JSONDecoder().decode(ShelfMemory.self, from: data)
        else { return ShelfMemory() }
        return memory
    }

    /// Where a continuous scroll sits within its current page, per publication. See
    /// ``ScrollOffsetMemory``.
    public func scrollOffsets() -> ScrollOffsetMemory {
        guard let data = defaults.data(forKey: scrollOffsetsKey),
              let memory = try? JSONDecoder().decode(ScrollOffsetMemory.self, from: data)
        else { return ScrollOffsetMemory() }
        return memory
    }

    public func save(_ memory: ScrollOffsetMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: scrollOffsetsKey)
    }
}
