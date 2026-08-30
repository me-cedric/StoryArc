internal import Foundation

internal import Kavita
internal import Persistence
internal import StoryArcCore

/// Keeping a server-backed reading list and the edits owed to it in step.
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

    /// One reading list, as the server currently has it.
    private struct Fetched {
        let shelf: ServerShelf
        let entries: [String]
    }

    /// Reconciles every server reading list that will answer.
    ///
    /// A list that does not answer is simply absent from what is merged, which leaves its
    /// edits queued and says nothing about them — that is the unreachable server, and
    /// `sources` is explicit that it is a normal state rather than a failure.
    static func reconcile(
        lists: [ServerShelf],
        store: ShelfEditStore,
        progress: KavitaProgressStore,
        now: Date = Date()
    ) async {
        var fetched: [Fetched] = []
        for shelf in lists {
            let client = KavitaClient(address: shelf.server.address)
            guard let items = try? await client.readingListItems(shelf.id) else { continue }
            fetched.append(
                Fetched(
                    shelf: shelf,
                    entries: items.sorted { $0.order < $1.order }.map { String($0.chapterId) }
                )
            )
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
            let named = lists.first { key($0) == conflict.shelf }?.title ?? ""
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

        await push(pull.toPush, of: lists, in: progress)
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

    /// How a server's reading list is named across a restart.
    static func key(_ shelf: ServerShelf) -> ShelfKey {
        ShelfKey(sourceID: shelf.server.id, shelfID: shelf.id)
    }

    /// Sends what is still owed, through the queue that already carries writes to a server.
    ///
    /// ``KavitaSync/flush(_:to:in:)`` is the one push path — a second one would double every
    /// append the moment both ran. What is new is the moment it runs at: until now nothing
    /// asked for a flush unless the reader opened that server's browser, so an edit made on
    /// the shelves screen waited for a screen they had no reason to visit.
    private static func push(
        _ owed: [ShelfEdit],
        of lists: [ServerShelf],
        in progress: KavitaProgressStore
    ) async {
        guard !owed.isEmpty else { return }
        let servers = Set(owed.map(\.shelf.sourceID))
        for id in servers {
            guard let page = lists.first(where: { $0.server.id == id })?.server else { continue }
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
