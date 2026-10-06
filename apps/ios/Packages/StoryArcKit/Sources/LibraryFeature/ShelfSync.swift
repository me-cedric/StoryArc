internal import Foundation

internal import Kavita
internal import Persistence
internal import StoryArcCore

/// Keeping a server-backed shelf and the edits owed to it in step.
///
/// `collections-and-reading-lists` asks for two things that are one round of work: an edit
/// made while the server was away is "pushed on reconnection", and an edit the server has
/// overtaken loses to it with the reader "told once what changed". Both need the server's
/// current version of the list, so both happen the moment it hands one over.
///
/// The decisions are not here. ``ShelfMerge`` holds the table, where a test can reach it
/// without a server. This is the part only a server can do: asking, sending, and writing the
/// answer down. Android's `ShelfSync` does the same three in the same order.
enum ShelfSync {

    /// One shelf, as the server currently has it.
    private struct Fetched {
        let shelf: ServerShelf
        let entries: [String]
    }

    /// Reconciles every server shelf that will answer.
    ///
    /// A shelf that does not answer is simply absent from what is merged, which leaves its
    /// edits queued and says nothing about them — that is the unreachable server, and
    /// `sources` is explicit that it is a normal state rather than a failure.
    ///
    /// **A collection is asked as well as a reading list, and only for its membership.** It
    /// carries no pending edit — nothing offers one — so the merge finds nothing to push and
    /// nothing to drop for it, and the whole of its round is the record it leaves behind.
    /// That record is what `home-screen`'s *Pinned shelves* then draws a pinned collection
    /// from without asking a server, which *The home surface never waits on a source* forbids.
    static func reconcile(
        shelves: [ServerShelf],
        store: ShelfEditStore,
        progress: KavitaProgressStore,
        now: Date = Date()
    ) async {
        var fetched: [Fetched] = []
        for shelf in shelves {
            guard let entries = await members(of: shelf) else { continue }
            fetched.append(Fetched(shelf: shelf, entries: entries))
        }
        guard !fetched.isEmpty else { return }

        let queue = store.queue()
        let pull = ShelfPull.merging(
            remote: fetched.map { ShelfSnapshot(shelf: key($0.shelf), entries: $0.entries) },
            baseline: { queue.baseline(for: $0) },
            pending: queue.edits
        )

        var settled = queue.dropping(pull.toDrop)
        for each in fetched {
            settled = settled.recording(
                ShelfSnapshot(shelf: key(each.shelf), entries: each.entries)
            )
        }
        for conflict in pull.conflicts {
            // The server won, so what it overrode must never be sent afterwards: the edit
            // leaves the transport queue as well as this one.
            forget(conflict.discarded, from: progress)
            let named = shelves.first { key($0) == conflict.shelf }?.title ?? ""
            settled = settled.noting(
                ShelfConflictNotice(
                    shelf: conflict.shelf,
                    shelfName: named,
                    discarded: conflict.discarded.map(\.title),
                    at: now
                )
            )
        }
        store.save(settled)

        await push(pull.toPush, of: shelves, in: progress)
    }

    /// What one shelf holds, named the way the thing that reads the record back joins on.
    ///
    /// A reading list answers with its chapters, in the server's order, because the order is
    /// the list's meaning. A collection answers with the *names* of its series, in the order
    /// the server listed them, because a collection groups series and this library's own idea
    /// of a series is its name — `LibraryRows` groups by nothing else, and a ``Publication``
    /// carries the name and no server series number at all. A series renamed on the server
    /// drops out of the pinned shelf until the next reconciliation, which then writes the new
    /// name down: the record heals itself, where a pin keyed on a title would not.
    ///
    /// `nil` where the server did not answer, so the caller can tell that apart from a shelf
    /// the server says is empty.
    private static func members(of shelf: ServerShelf) async -> [String]? {
        let client = KavitaClient(address: shelf.server.address)
        guard shelf.isList else {
            return (try? await client.collected(shelf.id)).map(collectionMembers)
        }
        guard let items = try? await client.readingListItems(shelf.id) else { return nil }
        return items.sorted { $0.order < $1.order }.map { String($0.chapterId) }
    }

    /// What a pinned collection records as its members: the names of its series. Pure, so the
    /// rule `HomePinnedShelves` filters by can be asserted without a server.
    static func collectionMembers(_ series: [KavitaSeries]) -> [String] {
        series.map(\.name)
    }

    /// Records an edit the server has not been told about yet.
    ///
    /// Written before the send is attempted rather than after it fails, because the two are
    /// not the same promise: an app killed between the tap and the timeout has still had the
    /// edit made in it. The next reconciliation settles it if it did in fact land.
    static func note(
        entry: Int,
        titled title: String,
        on shelf: ServerShelf,
        in store: ShelfEditStore,
        at moment: Date = Date()
    ) {
        store.update {
            $0.queueing(
                ShelfEdit(
                    shelf: key(shelf),
                    entry: String(entry),
                    title: title,
                    madeAt: moment
                )
            )
        }
    }

    /// How a server's shelf is named across a restart. The kind is in it because one server
    /// numbers its collections and its reading lists from one apiece.
    static func key(_ shelf: ServerShelf) -> ShelfKey {
        ShelfKey(
            sourceID: shelf.server.id,
            shelfID: shelf.id,
            kind: shelf.isList ? .readingList : .collection
        )
    }

    // MARK: Ordering

    /// Where one entry of a server reading list currently sits.
    ///
    /// Both halves are needed and neither is the other: Kavita addresses a move by the
    /// *entry* it minted, and this app knows the list by the chapters in it.
    struct Place: Sendable, Equatable {
        let item: Int
        let chapter: Int

        init(item: Int, chapter: Int) {
            self.item = item
            self.chapter = chapter
        }
    }

    /// One thing to ask the server for: move this entry from here to there.
    struct Move: Sendable, Equatable {
        let item: Int
        let from: Int
        let to: Int

        init(item: Int, from: Int, to: Int) {
            self.item = item
            self.from = from
            self.to = to
        }
    }

    /// The run of moves that turns the order a server holds into the order a reader made.
    ///
    /// Pure, and takes both sides as values, so the plan can be asserted without a server.
    /// Each move is planned against the order the moves before it leave behind, because that
    /// is the order the server will be in when it receives them — planning every move against
    /// the original positions sends coordinates the server has already invalidated.
    ///
    /// A wanted chapter the server does not hold is left out rather than moved: it is an
    /// entry this device believes in and the server does not, which is the append queue's
    /// business, not this one's. A held chapter the wanted order does not name keeps its
    /// place after the ones that are named, because the server may have gained it since.
    ///
    /// Android's `ShelfSync.moves` plans the same run.
    static func moves(from places: [Place], to wanted: [Int]) -> [Move] {
        var current = places
        var plan: [Move] = []
        var target = 0
        for chapter in wanted {
            guard let at = current.firstIndex(where: { $0.chapter == chapter }), at >= target
            else { continue }
            if at != target {
                plan.append(Move(item: current[at].item, from: at, to: target))
                let moved = current.remove(at: at)
                current.insert(moved, at: target)
            }
            target += 1
        }
        return plan
    }

    /// The rows of a server reading list, in the order the reader gave it.
    ///
    /// `collections-and-reading-lists` asks an edit made while the server is away to be
    /// "applied locally" — for a reorder that means the reader keeps looking at their own
    /// order, not the server's, for as long as the server has not taken it.
    ///
    /// Rows the wanted order does not name follow the ones it does, in the order they
    /// arrived in. Dropping them would lose a row the reader can see.
    static func arranged(_ rows: [ShelfEntry], by wanted: [String]) -> [ShelfEntry] {
        guard !wanted.isEmpty else { return rows }
        let named = wanted.compactMap { id in rows.first { $0.id == id } }
        let taken = Set(named.map(\.id))
        return named + rows.filter { !taken.contains($0.id) }
    }

    /// Sends what is still owed, through the queue that already carries writes to a server.
    ///
    /// ``KavitaSync/flush(_:to:in:)`` is the one push path — a second one would double every
    /// append the moment both ran. What is new is the moment it runs at: until now nothing
    /// asked for a flush unless the reader opened that server's browser, so an edit made on
    /// the shelves screen waited for a screen they had no reason to visit.
    private static func push(
        _ owed: [ShelfEdit],
        of shelves: [ServerShelf],
        in progress: KavitaProgressStore
    ) async {
        guard !owed.isEmpty else { return }
        let servers = Set(owed.map(\.shelf.sourceID))
        for id in servers {
            guard let page = shelves.first(where: { $0.server.id == id })?.server else { continue }
            await KavitaSync.flush(id, to: page.address, in: progress)
        }
    }

    /// Takes discarded edits out of the transport queue, so a later flush cannot resurrect
    /// what the server has already overruled.
    private static func forget(_ discarded: [ShelfEdit], from progress: KavitaProgressStore) {
        let dropped = Set(discarded.map { "\($0.shelf.shelfID):\($0.entry)" })
        let held = progress.unsent().filter { unsent in
            guard let list = unsent.listID else { return false }
            return dropped.contains("\(list):\(unsent.origin.chapterId)")
        }
        progress.sent(held)
    }
}
