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

    /// Puts a re-authorised source back where the old one stood.
    ///
    /// `sources` requires the app to offer "a single action to re-enter credentials" when
    /// one is refused. The point of replacing rather than removing and adding is everything
    /// that would otherwise be lost: the source's position in the order — which decides
    /// which of two sources wins for the same publication — and, because the identifier is
    /// the same, its downloads and its reading positions.
    ///
    /// The reader's own name for it survives too. They renamed it after adding it, and a
    /// re-authorisation is not the moment to hand the server's name back.
    ///
    /// A source that is no longer in the registry is not added: it was removed while the
    /// sheet was open, and putting it back would be the app arguing with the reader.
    public func replacing(_ source: Source) -> SourceRegistry {
        guard let existing = self[source.id] else { return self }
        return SourceRegistry(
            sources: sources.map { $0.id == source.id ? source.renamed(existing.displayName) : $0 },
            tombstones: tombstones
        )
    }

    /// Records what a source's connection looks like right now.
    ///
    /// State is deliberately not persisted — it describes a network, and a state read back
    /// from disk is a claim about the past. So something has to set it after a launch, and
    /// this is what that something calls.
    ///
    /// **A source that answers records the moment it answered**, which is the whole of
    /// `sources`' *A refresh that finished*. Until this line, `lastSuccessfulSync` was
    /// written in two places on iOS — both of them the moment a catalogue or a server was
    /// *added* — and in no place at all on Android, so the source detail screen's *Last
    /// sync* row showed the add moment for ever and a refresh that succeeded could not be
    /// told from one that never ran. It is the timestamp rather than a transient message
    /// because a message a reader looks away from says nothing at all.
    ///
    /// A refusal keeps the moment the source already had. That is the difference between a
    /// source that has never answered and one that answered yesterday, and both of those
    /// are things the detail screen has to be able to say.
    ///
    /// - Parameter moment: when this answer arrived. Explicit so a test can pin it; the
    ///   registry itself reads no clock anywhere else.
    public func marking(
        _ id: Source.ID,
        as state: SourceConnectionState,
        at moment: Date = .now
    ) -> SourceRegistry {
        SourceRegistry(
            sources: sources.map {
                guard $0.id == id else { return $0 }
                return state == .connected ? $0.with(state, answeredAt: moment) : $0.with(state)
            },
            tombstones: tombstones
        )
    }

    /// Records where a source points, for one that was stored before it had a locator.
    ///
    /// A migration, and a necessary one: a registry written before `locator` existed has
    /// `nil` there, so matching a folder to its source by locator finds nothing and adds
    /// the same folder a second time. That duplicate appeared on a real device.
    public func locating(_ id: Source.ID, at locator: String) -> SourceRegistry {
        SourceRegistry(
            sources: sources.map { $0.id == id ? $0.at(locator) : $0 },
            tombstones: tombstones
        )
    }

    /// Drops a source outright, leaving no tombstone.
    ///
    /// For a duplicate rather than for a removal. A tombstone says "the reader removed this
    /// and their progress should outlive it"; a row that should never have existed says
    /// nothing of the sort, and leaving one would hold thirty days of retention open for a
    /// source that was an artifact.
    public func discarding(_ id: Source.ID) -> SourceRegistry {
        SourceRegistry(sources: sources.filter { $0.id != id }, tombstones: tombstones)
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
    ///
    /// - Parameter identities: every publication this source held, at the moment it is
    ///   removed. 10.12: carried so the purge that follows thirty days later can tell
    ///   whether another source still holds the same book before it forgets the position;
    ///   10.14: the tombstone's own `kind` and `locator` are what let a later `add` of the
    ///   same place find it.
    public func removing(
        _ id: Source.ID,
        at moment: Date,
        holding identities: [PublicationIdentity] = []
    ) -> SourceRegistry {
        guard let source = self[id] else { return self }
        return SourceRegistry(
            sources: sources.filter { $0.id != id },
            tombstones: tombstones.filter { $0.sourceID != id }
                + [
                    SourceTombstone(
                        sourceID: id,
                        removedAt: moment,
                        kind: source.kind,
                        locator: source.locator,
                        identities: identities
                    ),
                ]
        )
    }

    /// The tombstones whose progress may now be forgotten, and a registry without them.
    ///
    /// Separated from ``removing(_:at:holding:)`` on purpose: deciding *when* the 30 days
    /// are up is a different question from deciding that a source is gone, and the caller
    /// that deletes reading positions should be the one that asks. Losing a reading
    /// position is the one thing ADR-0006 says the app must never do by accident.
    ///
    /// The whole tombstone, not only the id it was filed under: the caller needs the
    /// identities it carries to decide, publication by publication, whether anything else
    /// still holds the same book.
    public func collectingExpiredTombstones(
        at moment: Date,
        retention: TimeInterval = SourceTombstone.retention
    ) -> (registry: SourceRegistry, expired: [SourceTombstone]) {
        let expired = tombstones.filter { moment.timeIntervalSince($0.removedAt) >= retention }
        guard !expired.isEmpty else { return (self, []) }
        let kept = tombstones.filter { tombstone in
            !expired.contains { $0.sourceID == tombstone.sourceID }
        }
        return (SourceRegistry(sources: sources, tombstones: kept), expired)
    }

    /// A tombstone for the same place, if one is still open.
    ///
    /// 10.14: matched on `kind` and `locator` rather than on name — a reader who renamed
    /// the source before removing it should still have it recognised, and a `nil` locator
    /// never matches anything, because `nil == nil` would match every such source to the
    /// first tombstone of its kind.
    public func tombstone(for source: Source) -> SourceTombstone? {
        guard let locator = source.locator else { return nil }
        return tombstones.first { $0.kind == source.kind && $0.locator == locator }
    }

    /// The source that already stands for the place `source` names, if there is one.
    ///
    /// Task 26.5: the share form, used again for a share already in the list, added a second
    /// source with the same name and the same address. One place is one source.
    public func sameLocation(as source: Source) -> Source? {
        guard let locator = source.locator else { return nil }
        return sources.first { $0.id != source.id && $0.kind == source.kind && $0.locator == locator }
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
    /// The source's own kind and locator, so a later `add` of the same place can be told
    /// from an unrelated one of the same kind. 10.14.
    public let kind: SourceKind
    public let locator: String?
    /// Every publication this source held, so the purge can tell whether another source
    /// still needs the position before it forgets one. Empty for a tombstone written
    /// before 10.12, which decodes and purges exactly as it always has: nothing to check
    /// twice, nothing protected.
    public let identities: [PublicationIdentity]

    public init(
        sourceID: UUID,
        removedAt: Date,
        kind: SourceKind,
        locator: String? = nil,
        identities: [PublicationIdentity] = []
    ) {
        self.sourceID = sourceID
        self.removedAt = removedAt
        self.kind = kind
        self.locator = locator
        self.identities = identities
    }

    private enum CodingKeys: String, CodingKey {
        case sourceID, removedAt, kind, locator, identities
    }

    /// A tombstone written before 10.12/10.14 has none of the three new fields. Defaulted
    /// rather than refused: `SourceStore.registry()` drops the *whole* registry on a
    /// decode failure, and a safe default here costs nothing a tombstone needs for the
    /// 30-day purge, which only ever read `sourceID` and `removedAt`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(UUID.self, forKey: .sourceID)
        removedAt = try container.decode(Date.self, forKey: .removedAt)
        kind = try container.decodeIfPresent(SourceKind.self, forKey: .kind) ?? .localFolder
        locator = try container.decodeIfPresent(String.self, forKey: .locator)
        identities = try container.decodeIfPresent([PublicationIdentity].self, forKey: .identities) ?? []
    }
}

extension Source {
    /// The same source with its locator filled in.
    func at(_ locator: String) -> Source {
        Source(
            id: id,
            displayName: displayName,
            kind: kind,
            state: state,
            lastSuccessfulSync: lastSuccessfulSync,
            credentialReference: credentialReference,
            locator: locator
        )
    }

    /// The same source in a new connection state, and optionally at the moment it answered.
    func with(_ state: SourceConnectionState, answeredAt moment: Date? = nil) -> Source {
        Source(
            id: id,
            displayName: displayName,
            kind: kind,
            state: state,
            lastSuccessfulSync: moment ?? lastSuccessfulSync,
            credentialReference: credentialReference,
            locator: locator
        )
    }

    /// The same source, filed under a different identifier.
    ///
    /// 10.14: what lets a freshly-connected source take over a removed one's tombstone,
    /// id and all, so its reading positions resolve as the same publications again
    /// instead of under an identifier `ProgressStore` has never seen.
    public func rekeyed(to id: UUID) -> Source {
        Source(
            id: id,
            displayName: displayName,
            kind: kind,
            state: state,
            lastSuccessfulSync: lastSuccessfulSync,
            credentialReference: credentialReference,
            locator: locator
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
            credentialReference: credentialReference,
            locator: locator
        )
    }
}
