public import Foundation

/// What the reader chose on the end screen about a finished download (D7).
///
/// Two sets of download ids. **Kept**: the automatic sweep skips these from now on.
/// **Removed on close**: the reader asked for this download to go, and it goes the next
/// time the library appears, through the same undoable removal the sweep uses. Done then
/// rather than at the tap, because the undo is shown in the library: removed at the tap,
/// its ten seconds ran out behind the reader that was still open.
///
/// Its own small store rather than a field on `Download`: the sweep already asks
/// `DownloadStore` which download is finished, and these questions need only an id.
public struct CleanupChoices {
    private let defaults: UserDefaults
    private let keptKey = "app.storyarc.downloads.keptFromCleanup"
    private let removalKey = "app.storyarc.downloads.removeOnClose"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the sweep skips `id`'s download.
    public func isKept(_ id: String) -> Bool {
        ids(keptKey).contains(id)
    }

    /// Exempts `id`'s download from the sweep from now on, and withdraws a removal the
    /// reader asked for.
    public func keep(_ id: String) {
        save(ids(keptKey).union([id]), keptKey)
        save(ids(removalKey).subtracting([id]), removalKey)
    }

    /// Asks for `id`'s download to go when the reader closes, sweep or no sweep.
    public func removeOnClose(_ id: String) {
        save(ids(removalKey).union([id]), removalKey)
    }

    /// Whether `id`'s download goes when the reader closes: the reader asked for it, or
    /// the sweep is on and the reader has not kept it.
    public func isRemovedOnClose(_ id: String, automaticCleanupIsOn: Bool) -> Bool {
        ids(removalKey).contains(id) || (automaticCleanupIsOn && !isKept(id))
    }

    /// The removals the reader asked for, which this then forgets.
    public func takeRemovals() -> Set<String> {
        let removals = ids(removalKey)
        save([], removalKey)
        return removals
    }

    private func ids(_ key: String) -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return stored
    }

    private func save(_ ids: Set<String>, _ key: String) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: key)
    }
}
