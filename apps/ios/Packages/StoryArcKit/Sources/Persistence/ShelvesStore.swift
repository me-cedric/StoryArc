public import Foundation

public import StoryArcCore

/// Collections and reading lists, on disk.
///
/// A JSON blob in `UserDefaults`, for the reason ``SourceStore`` is one: the whole set is
/// read together to draw one screen, and a store that read it piecemeal would let two
/// halves of it disagree.
///
/// Only local groupings are written. A server's collections belong to the server and are
/// fetched, not remembered — `collections-and-reading-lists` makes the server's version win
/// on conflict, and a cached copy that outlived a server edit is exactly the stale claim
/// that rule exists to prevent.
public struct ShelvesStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.shelves"
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    public func shelves() -> Shelves {
        stored()?.shelves ?? Shelves()
    }

    /// The shelves the reader deleted, kept so a sync carries the deletion.
    public func removed() -> [ShelfTombstone] {
        stored()?.removed ?? []
    }

    /// Writes what a screen changed: each change is stamped and each deletion recorded.
    /// `library-sync` tasks 3.3 and 3.4; see ``ShelfStamps/stamped(before:removedBefore:after:removedAfter:now:)``.
    public func save(_ shelves: Shelves) {
        save(shelves, removed: removed())
    }

    /// Writes shelves and deletions together, as a sync or an import leaves them.
    public func save(_ shelves: Shelves, removed: [ShelfTombstone]) {
        let stamped = ShelfStamps.stamped(
            before: self.shelves(), removedBefore: self.removed(),
            after: shelves, removedAfter: removed, now: now()
        )
        restore(stamped.shelves, removed: stamped.removed)
    }

    /// Writes shelves and deletions exactly as given: the undo of a failed import or sync.
    public func restore(_ shelves: Shelves, removed: [ShelfTombstone]) {
        guard let data = try? JSONEncoder().encode(StoredShelves(shelves, removed: removed)) else { return }
        defaults.set(data, forKey: key)
    }

    private func stored() -> StoredShelves? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoredShelves.self, from: data)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

/// What is actually written.
private struct StoredShelves: Codable {
    let collections: [StoredCollection]
    let lists: [StoredList]
    /// Absent before `library-sync`, which `Decodable`'s synthesis reads as nil: no deletion.
    let removedShelves: [ShelfTombstone]?

    init(_ shelves: Shelves, removed: [ShelfTombstone]) {
        collections = shelves.collections
            .filter { $0.origin == .local }
            .map(StoredCollection.init)
        lists = shelves.lists.filter { $0.origin == .local }.map(StoredList.init)
        removedShelves = removed
    }

    var removed: [ShelfTombstone] { removedShelves ?? [] }

    var shelves: Shelves {
        Shelves(
            collections: collections.map(\.collection),
            lists: lists.map(\.list)
        )
    }
}

private struct StoredCollection: Codable {
    let id: UUID
    let name: String
    let members: [String]
    let coverMemberID: String?
    /// Absent before `library-sync`; read as the epoch, which any deletion outranks.
    let changedAt: Date?

    init(_ collection: PublicationCollection) {
        id = collection.id
        name = collection.name
        // Written as an array so the file is stable between launches, which makes a diff of
        // it readable when something goes wrong.
        members = collection.members.sorted()
        coverMemberID = collection.coverMemberID
        changedAt = collection.changedAt
    }

    var collection: PublicationCollection {
        PublicationCollection(
            id: id,
            name: name,
            members: Set(members),
            coverMemberID: coverMemberID,
            origin: .local,
            changedAt: changedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

private struct StoredList: Codable {
    let id: UUID
    let name: String
    let entries: [String]
    /// Absent on a record written before task 7.13, which `Decodable`'s synthesis reads as
    /// `nil` with no migration needed -- the same tolerance `StoredCollection.coverMemberID`
    /// already relies on by being optional.
    let coverMemberID: String?
    let changedAt: Date?

    init(_ list: ReadingList) {
        id = list.id
        name = list.name
        entries = list.entries
        coverMemberID = list.coverMemberID
        changedAt = list.changedAt
    }

    var list: ReadingList {
        ReadingList(
            id: id, name: name, entries: entries, coverMemberID: coverMemberID, origin: .local,
            changedAt: changedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}
