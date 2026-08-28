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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func shelves() -> Shelves {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredShelves.self, from: data)
        else { return Shelves() }
        return stored.shelves
    }

    public func save(_ shelves: Shelves) {
        guard let data = try? JSONEncoder().encode(StoredShelves(shelves)) else { return }
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

/// What is actually written.
private struct StoredShelves: Codable {
    let collections: [StoredCollection]
    let lists: [StoredList]

    init(_ shelves: Shelves) {
        collections = shelves.collections
            .filter { $0.origin == .local }
            .map(StoredCollection.init)
        lists = shelves.lists.filter { $0.origin == .local }.map(StoredList.init)
    }

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

    init(_ collection: PublicationCollection) {
        id = collection.id
        name = collection.name
        // Written as an array so the file is stable between launches, which makes a diff of
        // it readable when something goes wrong.
        members = collection.members.sorted()
        coverMemberID = collection.coverMemberID
    }

    var collection: PublicationCollection {
        PublicationCollection(
            id: id,
            name: name,
            members: Set(members),
            coverMemberID: coverMemberID,
            origin: .local
        )
    }
}

private struct StoredList: Codable {
    let id: UUID
    let name: String
    let entries: [String]

    init(_ list: ReadingList) {
        id = list.id
        name = list.name
        entries = list.entries
    }

    var list: ReadingList {
        ReadingList(id: id, name: name, entries: entries, origin: .local)
    }
}
