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
    private let changedAtKey = "app.storyarc.settingsChangedAt"
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
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

    /// When each setting last changed, by field name. `library-sync` task 3.5.
    public func changedAt() -> [String: Date] {
        guard let data = defaults.data(forKey: changedAtKey),
              let stamps = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return stamps
    }

    /// Writes what the reader changed, with each changed field stamped now.
    public func save(_ settings: AppSettings) {
        save(settings, changedAt: changedAt())
    }

    /// Writes settings with their moments, as an import leaves them. A field whose value changed
    /// while its moment did not is stamped now; see ``ChangeStamps/restamped(changed:before:after:now:)``.
    public func save(_ settings: AppSettings, changedAt stamps: [String: Date]) {
        let restamped = ChangeStamps.restamped(
            changed: SettingsStamps.changed(from: self.settings(), to: settings),
            before: changedAt(), after: stamps, now: now()
        )
        restore(settings, changedAt: restamped)
    }

    /// Writes settings and moments exactly as given: a sync, or the undo of a failed write.
    public func restore(_ settings: AppSettings, changedAt stamps: [String: Date]) {
        guard let data = try? JSONEncoder().encode(settings),
              let moments = try? JSONEncoder().encode(stamps)
        else { return }
        defaults.set(data, forKey: key)
        defaults.set(moments, forKey: changedAtKey)
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
