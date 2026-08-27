public import Foundation

/// The ordered list of configured sources, and every change that can be made to it.
///
/// `sources` requires "an ordered, persistent registry". Order is not decoration: the
/// same requirement says the combined library "lists titles from higher sources first
/// when two sources hold the same publication", so position carries meaning and a `Set`
/// would lose it.
///
/// A value type with pure operations, like ``ShelfMemory``. Every change returns a new
/// registry, which is what lets a store save the result of an edit rather than reasoning
/// about how the edit happened.
public struct SourceRegistry: Sendable, Equatable {
    /// In the order a reader put them, which is the order the library reads them.
    public private(set) var sources: [Source]

    /// Sources removed and not yet forgotten. See ``removing(_:at:)``.
    public private(set) var tombstones: [SourceTombstone]

    public init(sources: [Source] = [], tombstones: [SourceTombstone] = []) {
        self.sources = sources
        self.tombstones = tombstones
    }

    public subscript(id: Source.ID) -> Source? {
        sources.first { $0.id == id }
    }

    /// Adds a source at the end.
    ///
    /// At the end rather than the front: the order is the reader's, and a new source
    /// pushing itself above the ones they arranged would undo that arrangement.
    public func adding(_ source: Source) -> SourceRegistry {
        guard self[source.id] == nil else { return self }
        return SourceRegistry(sources: sources + [source], tombstones: tombstones)
    }

    /// Renames a source.
    ///
    /// A blank name is refused rather than stored. `sources` requires the name to appear
    /// "everywhere the source is referenced, including download attributions and error
    /// messages", and a blank one would make those sentences read as if a word were
    /// missing.
    public func renaming(_ id: Source.ID, to name: String) -> SourceRegistry {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return SourceRegistry(
            sources: sources.map { $0.id == id ? $0.renamed(trimmed) : $0 },
            tombstones: tombstones
        )
    }

    /// Moves a source to a new position.
    ///
    /// Takes the destination a drag reports, which is an index in the list *before* the
    /// move. Removing first and inserting after would land one place early for every
    /// downward drag.
    public func moving(_ id: Source.ID, to destination: Int) -> SourceRegistry {
        guard let from = sources.firstIndex(where: { $0.id == id }) else { return self }
        var moved = sources
        let source = moved.remove(at: from)
        let to = min(max(destination > from ? destination - 1 : destination, 0), moved.count)
        moved.insert(source, at: to)
        return SourceRegistry(sources: moved, tombstones: tombstones)
    }

    /// Records what a source's connection looks like right now.
    ///
    /// State is deliberately not persisted — it describes a network, and a state read back
    /// from disk is a claim about the past. So something has to set it after a launch, and
    /// this is what that something calls.
    public func marking(_ id: Source.ID, as state: SourceConnectionState) -> SourceRegistry {
        SourceRegistry(
            sources: sources.map { $0.id == id ? $0.with(state) : $0 },
            tombstones: tombstones
        )
    }

    /// Removes a source, and remembers that it was removed.
    ///
    /// The tombstone is the whole point. `sources` requires the app to retain "local
    /// reading progress for those publications for 30 days, so re-adding the same source
    /// restores where the user stopped". So removal must *not* cascade to the progress
    /// store, and something has to know when it is safe to.
    ///
    /// Re-adding a source with the same identifier clears its tombstone, which is what
    /// makes the retention promise true rather than merely delayed.
    public func removing(_ id: Source.ID, at moment: Date) -> SourceRegistry {
        guard self[id] != nil else { return self }
        return SourceRegistry(
            sources: sources.filter { $0.id != id },
            tombstones: tombstones.filter { $0.sourceID != id }
                + [SourceTombstone(sourceID: id, removedAt: moment)]
        )
    }

    /// The sources whose progress may now be forgotten, and a registry without them.
    ///
    /// Separated from ``removing(_:at:)`` on purpose: deciding *when* the 30 days are up
    /// is a different question from deciding that a source is gone, and the caller that
    /// deletes reading positions should be the one that asks. Losing a reading position
    /// is the one thing ADR-0006 says the app must never do by accident.
    public func collectingExpiredTombstones(
        at moment: Date,
        retention: TimeInterval = SourceTombstone.retention
    ) -> (registry: SourceRegistry, expired: [Source.ID]) {
        let expired = tombstones.filter { moment.timeIntervalSince($0.removedAt) >= retention }
        guard !expired.isEmpty else { return (self, []) }
        let kept = tombstones.filter { tombstone in
            !expired.contains { $0.sourceID == tombstone.sourceID }
        }
        return (SourceRegistry(sources: sources, tombstones: kept), expired.map(\.sourceID))
    }

    /// Re-adding a source the reader removed, with its progress intact.
    ///
    /// The tombstone goes, so the collection pass stops considering it.
    public func readding(_ source: Source) -> SourceRegistry {
        SourceRegistry(
            sources: sources + [source],
            tombstones: tombstones.filter { $0.sourceID != source.id }
        )
    }
}

/// A source that was removed, and when.
///
/// Kept so the progress belonging to its publications can outlive it for a while. See
/// ``SourceRegistry/removing(_:at:)``.
public struct SourceTombstone: Sendable, Equatable, Codable {
    /// Thirty days, from `sources`. Long enough that a reader who removed a server by
    /// mistake and noticed a week later loses nothing.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public let sourceID: UUID
    public let removedAt: Date

    public init(sourceID: UUID, removedAt: Date) {
        self.sourceID = sourceID
        self.removedAt = removedAt
    }
}

extension Source {
    /// The same source in a new connection state.
    func with(_ state: SourceConnectionState) -> Source {
        Source(
            id: id,
            displayName: displayName,
            kind: kind,
            state: state,
            lastSuccessfulSync: lastSuccessfulSync,
            credentialReference: credentialReference
        )
    }

    /// The same source under a new name.
    func renamed(_ name: String) -> Source {
        Source(
            id: id,
            displayName: name,
            kind: kind,
            state: state,
            lastSuccessfulSync: lastSuccessfulSync,
            credentialReference: credentialReference
        )
    }
}
