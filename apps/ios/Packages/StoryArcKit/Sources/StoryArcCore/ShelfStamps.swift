public import Foundation

/// Shelves with the deletions that go with them.
public struct StampedShelves: Sendable, Equatable {
    public var shelves: Shelves
    public var removed: [ShelfTombstone]
}

/// When each shelf changed, which shelves were deleted, and how two devices' shelves merge.
///
/// `library-sync` tasks 3.3 and 3.4. Android's `ShelfStamps` applies the same rules.
public enum ShelfStamps {

    /// The shelves a store writes, with each change the reader made stamped and each deletion
    /// recorded.
    ///
    /// A shelf whose content changed while its moment did not is stamped `now`; a moment the
    /// caller changed came from a merge and stays. A local shelf that is gone, with no
    /// tombstone for it, gets one. A shelf that comes back where a tombstone stands is stamped
    /// `now` and the tombstone goes: the reader put it back.
    public static func stamped(
        before: Shelves,
        removedBefore: [ShelfTombstone],
        after: Shelves,
        removedAfter: [ShelfTombstone],
        now: Date
    ) -> StampedShelves {
        let tombstoned = Set(removedAfter.map(\.id))
        let priorCollections = Dictionary(before.collections.map { ($0.id, $0) }) { first, _ in first }
        let priorLists = Dictionary(before.lists.map { ($0.id, $0) }) { first, _ in first }

        let collections = after.collections.map { shelf in
            var shelf = shelf
            if shelf.origin == .local, fresh(shelf, prior: priorCollections[shelf.id], tombstoned: tombstoned) {
                shelf.changedAt = now
            }
            return shelf
        }
        let lists = after.lists.map { shelf in
            var shelf = shelf
            if shelf.origin == .local, fresh(shelf, prior: priorLists[shelf.id], tombstoned: tombstoned) {
                shelf.changedAt = now
            }
            return shelf
        }

        let present = localIDs(after)
        let gone = localIDs(before).subtracting(present).subtracting(tombstoned)
            .sorted { $0.uuidString < $1.uuidString }
            .map { ShelfTombstone(id: $0, removedAt: now) }
        let known = removedAfter.filter { !present.contains($0.id) }
        // A tombstone this store held and the caller did not hand back still stands.
        let kept = removedBefore.filter { old in
            !present.contains(old.id) && !known.contains { $0.id == old.id }
        }
        return StampedShelves(shelves: Shelves(collections: collections, lists: lists), removed: known + kept + gone)
    }

    private static func fresh<S: StampedShelf>(_ shelf: S, prior: S?, tombstoned: Set<UUID>) -> Bool {
        guard let prior else {
            return tombstoned.contains(shelf.id) || shelf.changedAt == Date(timeIntervalSince1970: 0)
        }
        var unstamped = shelf
        unstamped.changedAt = prior.changedAt
        return unstamped != prior && shelf.changedAt == prior.changedAt
    }

    private static func localIDs(_ shelves: Shelves) -> Set<UUID> {
        Set(shelves.collections.filter { $0.origin == .local }.map(\.id))
            .union(shelves.lists.filter { $0.origin == .local }.map(\.id))
    }

    /// This device's shelves merged with the document's.
    ///
    /// Members are a union, so a member added on either device survives. The name and the
    /// cover come from the side that changed last. A reading list keeps the older side's order
    /// first and puts the other side's new entries after it. A tombstone wins over a shelf
    /// whose last change is not newer than the deletion; a shelf changed after it comes back.
    public static func merging(
        _ local: Shelves,
        removed localRemoved: [ShelfTombstone],
        with document: LibraryBody
    ) -> StampedShelves {
        let arriving = (document.removedShelves ?? []).map { ShelfTombstone(id: $0.id, removedAt: $0.removedAt) }
        var removed: [UUID: ShelfTombstone] = [:]
        for tombstone in localRemoved + arriving
        where (removed[tombstone.id]?.removedAt ?? .distantPast) < tombstone.removedAt {
            removed[tombstone.id] = tombstone
        }

        func settle<S: StampedShelf>(_ shelf: S?) -> S? {
            guard let shelf else { return nil }
            guard let tombstone = removed[shelf.id] else { return shelf }
            if ChangeStamps.seconds(shelf.changedAt) <= ChangeStamps.seconds(tombstone.removedAt) { return nil }
            removed[shelf.id] = nil
            return shelf
        }

        let mineCollections = local.collections.filter { $0.origin == .local }
        let theirCollections = document.collections.map(collection)
        let collections = ids(mineCollections, theirCollections).compactMap { id in
            settle(pair(mineCollections.first { $0.id == id }, theirCollections.first { $0.id == id }, union))
        }
        let mineLists = local.lists.filter { $0.origin == .local }
        let theirLists = document.readingLists.map(list)
        let lists = ids(mineLists, theirLists).compactMap { id in
            settle(pair(mineLists.first { $0.id == id }, theirLists.first { $0.id == id }, union))
        }
        return StampedShelves(
            shelves: Shelves(
                collections: local.collections.filter { $0.origin != .local } + collections,
                lists: local.lists.filter { $0.origin != .local } + lists
            ),
            removed: removed.values.sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        )
    }

    /// This device's ids in its order, then the document's new ones in theirs.
    private static func ids<S: StampedShelf>(_ mine: [S], _ theirs: [S]) -> [UUID] {
        let held = mine.map(\.id)
        return held + theirs.map(\.id).filter { !held.contains($0) }
    }

    private static func pair<S>(_ mine: S?, _ theirs: S?, _ union: (S, S) -> S) -> S? {
        if let mine, let theirs { return union(mine, theirs) }
        return mine ?? theirs
    }

    private static func newer(_ mine: Date, _ theirs: Date) -> Bool {
        ChangeStamps.seconds(theirs) > ChangeStamps.seconds(mine)
    }

    private static func union(_ mine: PublicationCollection, _ theirs: PublicationCollection) -> PublicationCollection {
        var last = newer(mine.changedAt, theirs.changedAt) ? theirs : mine
        last.members = mine.members.union(theirs.members)
        last.changedAt = max(mine.changedAt, theirs.changedAt)
        return last
    }

    private static func union(_ mine: ReadingList, _ theirs: ReadingList) -> ReadingList {
        var last = newer(mine.changedAt, theirs.changedAt) ? theirs : mine
        // The older side's order first. On the same second this device's order goes first, as
        // an import keeps it.
        let mineFirst = !newer(theirs.changedAt, mine.changedAt)
        let (first, second) = mineFirst ? (mine, theirs) : (theirs, mine)
        last.entries = first.entries + second.entries.filter { !first.entries.contains($0) }
        last.changedAt = max(mine.changedAt, theirs.changedAt)
        return last
    }

    private static func collection(_ arriving: DocumentCollection) -> PublicationCollection {
        PublicationCollection(
            id: arriving.id,
            name: arriving.name,
            members: Set(arriving.members),
            coverMemberID: arriving.coverMemberId,
            changedAt: arriving.changedAt ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func list(_ arriving: DocumentReadingList) -> ReadingList {
        ReadingList(
            id: arriving.id,
            name: arriving.name,
            entries: arriving.entries,
            coverMemberID: arriving.coverMemberId,
            changedAt: arriving.changedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

/// What the two shelf kinds share for stamping.
protocol StampedShelf: Equatable {
    var id: UUID { get }
    var changedAt: Date { get set }
}

extension PublicationCollection: StampedShelf {}
extension ReadingList: StampedShelf {}
