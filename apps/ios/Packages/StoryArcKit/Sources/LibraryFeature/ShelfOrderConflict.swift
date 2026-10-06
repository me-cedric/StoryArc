internal import Foundation
internal import Kavita
internal import Persistence
internal import StoryArcCore

/// `collections-and-reading-lists` task 7.4: whether a server reading list moved since the
/// baseline a reader's drag was planned against, and what to send when it did not.
///
/// Split out of `KavitaSync.swift`, which is at its own line cap: this is the one function
/// that grew past the cap, so it is the one that moved.
extension KavitaSync {
    /// Asks the server for the moves that turn its own order into the reader's, unless the
    /// server has moved since `baseline` — in which case nothing is sent and `onConflict` is
    /// told instead, so `flush`'s caller can drop the stale order rather than hold it for
    /// ever.
    ///
    /// `baseline` nil skips the check and sends exactly as every caller did before this task.
    static func reorderCheckingBaseline(
        _ listID: Int,
        to order: [Int],
        baseline: [Int]?,
        onConflict: (@Sendable (Int) -> Void)?,
        through client: KavitaClient
    ) async throws {
        let items = try await client.readingListItems(listID).sorted { $0.order < $1.order }
        if let baseline, items.map(\.chapterId) != baseline {
            onConflict?(listID)
            return
        }
        let places = items.map { ShelfSync.Place(item: $0.id, chapter: $0.chapterId) }
        for move in ShelfSync.moves(from: places, to: order) {
            try await client.moveInList(listID, item: move.item, from: move.from, to: move.to)
        }
    }

    /// A drag on a server list: the order it makes, and the baseline its send checks first.
    /// `nil` when either place is not a row.
    ///
    /// The baseline is the order the reader saw before this drag. When nothing is held, that
    /// is the server's order: the order the list opened in, or the order of the reader's last
    /// drag after the server took it. A baseline kept from when the view opened goes stale
    /// after the first drag the server takes, and every later drag of that visit is then
    /// dropped as a conflict with the reader's own earlier drag.
    static func dragged(_ held: [String], from: Int, to destination: Int) -> (order: [Int], baseline: [Int])? {
        guard from < held.count, destination <= held.count else { return nil }
        var moved = held
        moved.insert(moved.remove(at: from), at: destination > from ? destination - 1 : destination)
        return (moved.compactMap(Int.init), held.compactMap(Int.init))
    }

    /// What the rows show once a drag's send has settled: the server's own order when it kept
    /// that order over a stale drag, because the server's order wins. `nil` when the server
    /// holds `order`, or did not answer, and the rows already show the right order.
    static func settledRows(
        _ listID: Int,
        sent order: [Int],
        through client: KavitaClient
    ) async -> [KavitaReadingListItem]? {
        guard let items = try? await client.readingListItems(listID) else { return nil }
        let now = items.sorted { $0.order < $1.order }
        return now.map(\.chapterId) == order ? nil : now
    }

    /// Writes the notice a dropped order owes the reader — ``KavitaListView``'s own call
    /// into ``reorderCheckingBaseline``'s `onConflict`, lifted out to keep that call a
    /// one-liner.
    static func noteOrderConflict(sourceID: String, listID: Int, shelfName: String) {
        let shelf = ShelfKey(sourceID: sourceID, shelfID: listID)
        ShelfEditStore().update {
            $0.noting(ShelfConflictNotice(shelf: shelf, shelfName: shelfName, at: Date(), isOrder: true))
        }
    }
}

/// Task 7.5: the reconnection half of "applied locally, marked pending, and pushed on
/// reconnection" — split out of `LibrarySourceHealth.swift`, which is at its own line cap.
extension LibraryModel {
    /// Reconciles and flushes every server named in `listCapable`, the moment a probe finds
    /// it reachable — rather than waiting for a reader to open the one screen that used to
    /// drive this.
    @MainActor
    func reconcileAndFlush(_ listCapable: [KavitaPage]) async {
        guard !listCapable.isEmpty else { return }
        let editStore = ShelfEditStore()
        let queue = KavitaProgressStore()
        for page in listCapable {
            let shelves = serverLists.filter { $0.server.id == page.id }
            await ShelfSync.reconcile(shelves: shelves, store: editStore, progress: queue)
            await KavitaSync.flush(
                page.id,
                to: page.address,
                in: queue,
                // A position delivered here is stamped as synced, as the browser's own flush
                // stamps it, so the next pull does not read it as changed on this device.
                progress: progressStore,
                onOrderConflict: { listID in
                    let shelfName = shelves.first { $0.id == listID }?.title ?? ""
                    KavitaSync.noteOrderConflict(sourceID: page.id, listID: listID, shelfName: shelfName)
                }
            )
        }
    }
}
