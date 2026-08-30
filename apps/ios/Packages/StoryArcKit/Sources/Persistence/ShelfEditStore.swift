public import Foundation

public import StoryArcCore

/// Edits owed to a server, on disk.
///
/// A JSON blob in `UserDefaults`, for the reason ``ShelvesStore`` is one: the whole queue is
/// read together to decide one reconciliation, and a store that read it piecemeal would let
/// an edit outlive the baseline that justifies pushing it.
///
/// Durable is the entire point. `collections-and-reading-lists` promises that an edit made
/// "while the server is unreachable" is "pushed on reconnection", and the reader who made it
/// on a train has closed the app long before the server is back. An edit that lived in a
/// view model would be gone by then.
///
/// `@unchecked Sendable` for the reason ``KavitaProgressStore`` is: `UserDefaults` is
/// documented as thread-safe but is not marked so, and the reconciliation runs off the main
/// actor.
public struct ShelfEditStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.shelfEdits"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func queue() -> ShelfEditQueue {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(ShelfEditQueue.self, from: data)
        else { return ShelfEditQueue() }
        return stored
    }

    public func save(_ queue: ShelfEditQueue) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        defaults.set(data, forKey: key)
    }

    /// Reads, changes and writes in one call, so no caller has to remember the third step.
    public func update(_ change: (ShelfEditQueue) -> ShelfEditQueue) {
        save(change(queue()))
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
