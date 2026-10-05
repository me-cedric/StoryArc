internal import Foundation

internal import StoryArcCore

/// One pinned shelf, resolved to what the home surface can draw.
///
/// Carries its own name because that is the heading — the shelf is the reader's, or a
/// server's, so no string resource can name it — and its own publications because the three
/// kinds resolve their members three different ways and the view must not care which.
struct PinnedShelfRow: Identifiable {
    let id: String
    let name: String
    let publications: [Publication]
}

/// The shelves a reader pinned, each resolved to the publications this device holds.
///
/// `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the home
/// surface as a shelf of its own". A server's shelf is one of those, because
/// `collections-and-reading-lists` says it is "the same kind of object as locally created
/// ones" — and it reaches here without a request, because *The home surface never waits on a
/// source* forbids one. ``ShelfSync`` writes down what each server reading list held the last
/// time it answered, and `members` is that record read back.
///
/// **A server *collection* has no such record**, because ``ShelfSync`` reconciles reading
/// lists alone. A pinned one is still ordered ahead of the unpinned shelves on the home
/// surface's Collections shelf, and it draws no row of its own until something writes a
/// collection's membership down — which is *A shelf that would be empty* rather than a
/// silent failure.
///
/// **A collection is never asked, and that is a correctness rule rather than an economy.**
/// ``ShelfKey`` names a source and a number and not a kind, and a Kavita server numbers its
/// collections and its reading lists from one apiece — so asking for collection 1's members
/// returns reading list 1's. Seen on a simulator on 2026-10-05: a pinned *Staff picks* drew
/// *Start here*'s three covers, under its own name.
///
/// **A shelf that resolves to nothing is not returned**, per *A shelf that would be empty*.
/// That covers more than a collection the reader emptied: a pinned shelf whose members are
/// all on a source no scan has reached resolves to nothing too, and a heading over no covers
/// would be the surface waiting on something — the one thing it must never look like it is
/// doing. A pin whose shelf has been deleted is simply absent, and the stored pin is left
/// alone rather than tidied up: writing to storage while drawing turns a redraw into a write.
///
/// Collections, then the reader's lists, then the servers' — the order the shelves screen
/// shows them in, so a reader who pinned two things meets them here in the order they met
/// them there. Pure and free of the view, so Android's `pinnedShelves` can answer the same
/// cases.
func pinnedShelfRows(
    _ pinned: PinnedShelves,
    shelves: Shelves,
    remembered: [RememberedShelf] = [],
    members: (ShelfKey) -> [String]? = { _ in nil },
    publications: [Publication]
) -> [PinnedShelfRow] {
    let byID = Dictionary(publications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    // A server reading list names its members by the server's own chapter numbering, and a
    // publication's own id prefers its local path once the file has been downloaded — so the
    // join is on the server identity rather than on ``Publication/id``.
    let byRemote = Dictionary(
        publications.compactMap { publication -> (String, Publication)? in
            guard let server = publication.identity.serverIdentifier else { return nil }
            return ("\(server.sourceID.uuidString):\(server.remoteID)", publication)
        },
        uniquingKeysWith: { first, _ in first }
    )

    let collections = shelves.collections
        .filter { pinned.contains(.collection($0.id)) }
        .map { collection in
            PinnedShelfRow(
                id: "collection:\(collection.id.uuidString)",
                name: collection.name,
                publications: publications.filter { collection.members.contains($0.id) }
            )
        }

    // A reading list keeps its own order, which is the whole difference between the two
    // types — so the entries are walked rather than the library filtered.
    let lists = shelves.lists
        .filter { pinned.contains(.list($0.id)) }
        .map { list in
            PinnedShelfRow(
                id: "list:\(list.id.uuidString)",
                name: list.name,
                publications: list.entries.compactMap { byID[$0] }
            )
        }

    let server = remembered
        .filter { pinned.contains($0.pin) }
        .map { shelf in
            let key = ShelfKey(sourceID: shelf.sourceID.uuidString, shelfID: shelf.serverID)
            return PinnedShelfRow(
                id: shelf.id,
                name: shelf.title,
                // Ordered by the server's own order, as a local list is by the reader's: the
                // record `ShelfSync` keeps is already sorted by the list's position.
                publications: shelf.kind == .readingList
                    ? (members(key) ?? []).compactMap {
                        byRemote["\(shelf.sourceID.uuidString):chapter:\($0)"]
                    }
                    : []
            )
        }

    return (collections + lists + server).filter { !$0.publications.isEmpty }
}
