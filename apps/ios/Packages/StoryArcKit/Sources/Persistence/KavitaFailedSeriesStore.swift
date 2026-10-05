public import Foundation

/// Series whose volumes call failed while a Kavita source's continued read passed over them,
/// kept so they get another try instead of staying lost until the whole continuation runs
/// again.
///
/// `sources`' *More from a source than the library holds* keeps a page moving past a series
/// it cannot read right now — one unreadable series must not cost a reader the rest of the
/// page. Before this store existed, that series was gone for good: the page that skipped it
/// never asks for it again, so nothing short of the whole first-slice-and-continuation read
/// starting over would have given it a second chance, and `SourceReadProgressStore` now makes
/// sure that never happens on its own. Android's `KavitaFailedSeriesStore` is the same store.
public struct KavitaFailedSeriesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.kavita-failed-series"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The series ids of this source still waiting for a successful volumes call.
    public func pending(for sourceID: UUID) -> Set<Int> {
        stored()[sourceID.uuidString] ?? []
    }

    /// Replaces this source's whole pending set.
    ///
    /// The whole set each time rather than an add or a remove: the caller already knows
    /// which ids still fail after its own retry pass, and a store that merged partial writes
    /// could resurrect an id a caller had just confirmed had succeeded.
    public func record(_ pending: Set<Int>, for sourceID: UUID) {
        var all = stored()
        if pending.isEmpty {
            guard all.removeValue(forKey: sourceID.uuidString) != nil else { return }
        } else {
            all[sourceID.uuidString] = pending
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets a source's pending retries outright. Called when the source itself is gone.
    public func clear(for sourceID: UUID) {
        var all = stored()
        guard all.removeValue(forKey: sourceID.uuidString) != nil else { return }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets every source's pending retries. Used by a reset, and by the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
    }

    private func stored() -> [String: Set<Int>] {
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([String: Set<Int>].self, from: data)
        else { return [:] }
        return all
    }
}
