import Foundation
import StoryArcCore

/// A shelf in the sidebar or on Home: a collection or a reading list.
struct ShelfRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case collection, list }

    let pin: ShelfPin
    let name: String
    let kind: Kind
    let count: Int
    let isPinned: Bool

    var id: String { pin.token }
    /// True when nothing is on the shelf yet.
    var isEmpty: Bool { count < 1 }

    var symbolName: String {
        switch kind {
        case .collection: "square.stack"
        case .list: "list.number"
        }
    }
}

/// One entry of a reading list as the shelf page draws it.
struct ShelfListEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let position: Int
    /// The publication, when it is still in the library.
    let publication: Publication?
    /// An edit made while its server was away, not yet pushed: drawn grey.
    let isPending: Bool

    var isAvailable: Bool { publication != nil || isPending }
}

/// The shelves on Home: collections, then reading lists, each absent when there are none.
struct HomeShelves: Equatable, Sendable {
    let collections: [ShelfRow]
    let lists: [ShelfRow]

    var isEmpty: Bool { collections.isEmpty && lists.isEmpty }
}

/// Collections and reading lists for the Mac, as pure rules over StoryArcKit's `Shelves`.
///
/// `collections-and-reading-lists` and `home-screen`'s shelves. The model is the package's
/// (`Shelves`, `PinnedShelves`, `ShelfEditQueue`); what is here is the Mac's reading of it:
/// the sidebar's order (pinned first, then by name), a collection's members in title order,
/// a list's entries in the reader's order with an unpushed edit drawn grey at the end, and
/// Home's two shelves. Asserted in `ShelvesModelTests`.
enum MacShelves {
    static func sidebar(_ shelves: Shelves, pins: PinnedShelves) -> [ShelfRow] {
        let home = home(shelves, pins: pins)
        return pins.ordering(home.collections + home.lists, by: \.pin)
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned { return lhs.element.isPinned }
                let order = lhs.element.name.localizedStandardCompare(rhs.element.name)
                return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
            }
            .map(\.element)
    }

    static func home(_ shelves: Shelves, pins: PinnedShelves) -> HomeShelves {
        let collections = shelves.collections.map { collection in
            ShelfRow(
                pin: .collection(collection.id), name: collection.name, kind: .collection,
                count: collection.members.count, isPinned: pins.contains(.collection(collection.id))
            )
        }
        let lists = shelves.lists.map { list in
            ShelfRow(
                pin: .list(list.id), name: list.name, kind: .list,
                count: list.entries.count, isPinned: pins.contains(.list(list.id))
            )
        }
        return HomeShelves(
            collections: pins.ordering(byName(collections), by: \.pin),
            lists: pins.ordering(byName(lists), by: \.pin)
        )
    }

    private static func byName(_ rows: [ShelfRow]) -> [ShelfRow] {
        rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func collections(containing member: String, in shelves: Shelves) -> [PublicationCollection] {
        shelves.collections(containing: member)
    }

    /// Adds publications to a shelf: a set to a collection, the end of a list in the order given.
    static func adding(_ ids: [String], to pin: ShelfPin, in shelves: Shelves) -> Shelves {
        switch pin {
        case let .collection(id): shelves.adding(Set(ids), to: id)
        case let .list(id): shelves.appending(ids, to: id)
        case .server: shelves
        }
    }

    /// A shelf's members still in the library: a collection's in title order, a list's in its own.
    static func members(of pin: ShelfPin, in shelves: Shelves, library: [Publication]) -> [Publication] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        switch pin {
        case let .collection(id):
            let members = shelves.collections.first { $0.id == id }?.members ?? []
            return members.compactMap { byID[$0] }
                .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case let .list(id):
            return (shelves.lists.first { $0.id == id }?.entries ?? []).compactMap { byID[$0] }
        case .server:
            return []
        }
    }

    /// A list's entries in the reader's order, then any edit still owed to its server, grey.
    static func entries(
        of listID: UUID, in shelves: Shelves, library: [Publication], pending: [ShelfEdit]
    ) -> [ShelfListEntry] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let held = shelves.lists.first { $0.id == listID }?.entries ?? []
        var entries = held.enumerated().map { index, id in
            ShelfListEntry(
                id: id, title: byID[id]?.displayTitle ?? id, position: index + 1,
                publication: byID[id], isPending: false
            )
        }
        for edit in pending where !held.contains(edit.entry) {
            entries.append(ShelfListEntry(
                id: edit.entry, title: edit.title, position: entries.count + 1, publication: nil, isPending: true
            ))
        }
        return entries
    }

    /// How far through a reading list the reader is: its entries marked finished. A collection
    /// has no position, so Home never states one for it (`home-screen`).
    static func readThrough(_ listID: UUID, in shelves: Shelves, finished: Set<String>) -> Int {
        (shelves.lists.first { $0.id == listID }?.entries ?? []).filter(finished.contains).count
    }

    /// The name of the shelf a pin names, for a page title.
    static func name(of pin: ShelfPin, in shelves: Shelves) -> String? {
        switch pin {
        case let .collection(id): shelves.collections.first { $0.id == id }?.name
        case let .list(id): shelves.lists.first { $0.id == id }?.name
        case .server: nil
        }
    }
}
