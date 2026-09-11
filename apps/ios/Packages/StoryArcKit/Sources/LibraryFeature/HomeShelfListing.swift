internal import Foundation

internal import StoryArcCore

/// Where a card on the home surface leads.
enum HomeShelfDestination: Hashable {
    /// A shelf the reader made here. Its own detail screen, as from the shelves screen.
    case onDevice(UUID)

    /// A shelf a server defined. The record is what opens it again, because the server's own
    /// numbering is the only name it has.
    case onServer(RememberedShelf)
}

/// One shelf as the home surface names it.
///
/// Deliberately not a ``PublicationCollection`` or a ``ReadingList``: the home surface lists
/// both kinds and a server's as well, and the three carry different amounts of truth. What
/// they have in common is a name, some artwork and somewhere to go, which is exactly this.
struct HomeShelfSummary: Identifiable {
    let kind: RememberedShelfKind
    let name: String
    /// How many publications are in it, or `nil` for a server's shelf whose size this device
    /// does not know. `nil` draws no count rather than a zero that would be a lie.
    let count: Int?
    /// The source's name, or `nil` for a shelf the reader made here.
    let sourceName: String?
    /// The publications behind the composite, in the order they are drawn.
    ///
    /// Resolved here rather than left as identities, so this file stays the only place that
    /// knows which four a shelf stands on. A member this device does not hold is left out,
    /// which is the one place the home surface's composite is narrower than the shelves
    /// screen's: that one keeps the identity and blanks its quadrant. A remembered shelf has no
    /// local members at all, so its list is empty and its card is the cover-shaped blank.
    let tiles: [Publication]
    /// How many of an ordered shelf's entries are behind the reader. `nil` for a collection,
    /// which has no order and therefore no position in one — and which is what makes the two
    /// kinds tell apart on a card as well as in a heading.
    let finished: Int?
    let destination: HomeShelfDestination

    /// How far through the shelf the reader is, or `nil` where there is no order to be
    /// part-way through. Counted rather than stored, so the rail and the count under the name
    /// cannot disagree.
    var progress: ShelfProgress? {
        guard let finished, let count else { return nil }
        return ShelfProgress(done: finished, total: count)
    }

    /// Stable across a rename and unique across the two kinds and the two origins.
    var id: String {
        switch destination {
        case let .onDevice(id): "local:\(id.uuidString)"
        case let .onServer(shelf): shelf.token
        }
    }
}

/// The reader's shelves, as two shelves of the home surface.
///
/// `collections-and-reading-lists`, *Shelves on the home surface*: two and not one, because a
/// reading list is ordered and a collection is not, and because merging them would need a name
/// for a merged idea that neither platform ships. Each half is drawn only when it holds
/// something, so a reader with collections and no lists meets one heading.
struct HomeShelfListing {
    var collections: [HomeShelfSummary] = []
    var lists: [HomeShelfSummary] = []

    var isEmpty: Bool { collections.isEmpty && lists.isEmpty }
}

/// Assembles ``HomeShelfListing`` out of local curation alone.
///
/// Pure, and asserted on the host the way `HomeShelves` is. **Nothing here reaches a source.**
/// `home-screen` requires the home surface to render "with the same shelves in the same order
/// as when the sources are up", so a server's shelf arrives as a ``RememberedShelf`` — a
/// record of what that server last answered — rather than as a request.
///
/// Android's `HomeShelfIndex` is the same assembly.
enum HomeShelfIndex {

    /// - Parameters:
    ///   - openableSources: the sources the app can actually open right now, by id, with the
    ///     name to label them by. A remembered shelf whose source is not here is left out: the
    ///     source has been removed, or has lost the key its shelf would need, and a card that
    ///     cannot lead anywhere is worse than no card. The record itself is left alone —
    ///     writing to storage while drawing turns a redraw into a write.
    ///   - finished: which publications are read, for a reading list's position.
    ///   - pinned: the reader's own order. Pinned shelves lead each half, stable within both
    ///     groups, by the one rule ``PinnedShelves/ordering(_:by:)`` already applies on the
    ///     shelves screen.
    static func assemble(
        shelves: Shelves,
        publications: [Publication],
        remembered: [RememberedShelf] = [],
        openableSources: [UUID: String] = [:],
        finished: Set<String> = [],
        pinned: PinnedShelves = PinnedShelves()
    ) -> HomeShelfListing {
        let byID = Dictionary(publications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tiles: ([String]) -> [Publication] = { ids in ids.compactMap { byID[$0] } }

        let collections = pinned
            .ordering(shelves.collections) { .collection($0.id) }
            .map { collection in
                HomeShelfSummary(
                    kind: .collection,
                    name: collection.name,
                    count: collection.members.count,
                    sourceName: collection.origin.sourceID.flatMap { openableSources[$0] },
                    tiles: tiles(CompositeCover.tiles(of: collection)),
                    finished: nil,
                    destination: .onDevice(collection.id)
                )
            }

        let lists = pinned
            .ordering(shelves.lists) { .list($0.id) }
            .map { list in
                HomeShelfSummary(
                    kind: .readingList,
                    name: list.name,
                    count: list.entries.count,
                    sourceName: list.origin.sourceID.flatMap { openableSources[$0] },
                    tiles: tiles(ShelfCover.tiles(of: list)),
                    finished: list.position { finished.contains($0) },
                    destination: .onDevice(list.id)
                )
            }

        let server = remembered
            .filter { openableSources[$0.sourceID] != nil }
            .map { shelf in
                HomeShelfSummary(
                    kind: shelf.kind,
                    name: shelf.title,
                    count: nil,
                    sourceName: openableSources[shelf.sourceID],
                    tiles: [],
                    finished: nil,
                    destination: .onServer(shelf)
                )
            }

        return HomeShelfListing(
            collections: collections + server.filter { $0.kind == .collection },
            lists: lists + server.filter { $0.kind == .readingList }
        )
    }

    /// What a fetch found, as the record to write down.
    ///
    /// The whole record, replacing whatever was there: the fetch asks every configured server,
    /// so its answer is the complete set and a merge would only keep shelves that have since
    /// been deleted on a server. Pure so a test can assert that, which is the half a screen
    /// cannot show.
    static func remembering(_ fetched: [ServerShelf]) -> [RememberedShelf] {
        fetched.compactMap { shelf in
            guard let source = UUID(uuidString: shelf.server.id) else { return nil }
            return RememberedShelf(
                kind: shelf.isList ? .readingList : .collection,
                sourceID: source,
                serverID: shelf.id,
                title: shelf.title
            )
        }
    }
}

extension ServerShelves {
    /// What to write down after one round of asking every server, or `nil` when none answered.
    ///
    /// Answering with nothing is not the same as not answering: a server whose last collection
    /// was deleted must lose its names, and a reader on a train must keep theirs. The
    /// capability lists are what tell the two apart, which is why they are kept beside the
    /// shelves rather than inferred from them.
    var record: String? {
        guard !listCapable.isEmpty || !collectionCapable.isEmpty else { return nil }
        return RememberedShelf.stored(HomeShelfIndex.remembering(shelves))
    }
}
