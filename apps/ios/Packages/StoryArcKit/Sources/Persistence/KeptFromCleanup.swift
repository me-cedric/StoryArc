public import Foundation

/// Downloads exempted from the automatic sweep.
///
/// Decision D7: with automatic cleanup on, the end screen states that this download
/// goes when the reader closes, with a "Keep" action that exempts it. Its own small
/// store rather than a field on `Download` — the sweep already asks `DownloadStore`
/// which download is finished, and asking it which is exempt needs only an id, not a
/// change to the download record or how it is stored.
public struct KeptFromCleanup {
    private let defaults: UserDefaults
    private let key = "app.storyarc.downloads.keptFromCleanup"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether `id`'s download has been kept from the sweep.
    public func contains(_ id: String) -> Bool {
        ids().contains(id)
    }

    /// Exempts `id`'s download from the sweep, from now on.
    public func keep(_ id: String) {
        var current = ids()
        current.insert(id)
        save(current)
    }

    private func ids() -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return stored
    }

    private func save(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: key)
    }
}
