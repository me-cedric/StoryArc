public import Foundation

public import StoryArcCore

/// Where ``AppSettings`` lives between launches.
///
/// Beside `ReaderPreferences` and `LibraryPreferences` rather than inside either.
/// `settings-and-about` groups settings by what a reader is looking for, and those
/// groups cut across the stores — appearance belongs to no reader and no library — so
/// a third store is the honest shape rather than a wing of one of the others.
public struct SettingsStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// What the reader has chosen, or the defaults.
    ///
    /// Unreadable stored data reads as no data, the same rule the theme store uses:
    /// a setting is a preference, and losing one is worth far less than refusing to
    /// start.
    public func settings() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .defaults }
        return stored
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    /// Puts everything this store holds back to its default.
    ///
    /// `settings-and-about` requires a reset to confirm first and to state that
    /// "sources, downloads, and reading progress are not affected". That statement is
    /// true because of what ``AppSettings`` *is*, not because this method is careful:
    /// it holds none of them, so there is nothing here to be careful about.
    public func reset() {
        save(.defaults)
    }
}
