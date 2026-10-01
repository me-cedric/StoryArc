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
        onConflict: (@Sendable () -> Void)?,
        through client: KavitaClient
    ) async throws {
        let items = try await client.readingListItems(listID).sorted { $0.order < $1.order }
        if let baseline, items.map(\.chapterId) != baseline {
            onConflict?()
            return
        }
        let places = items.map { ShelfSync.Place(item: $0.id, chapter: $0.chapterId) }
        for move in ShelfSync.moves(from: places, to: order) {
            try await client.moveInList(listID, item: move.item, from: move.from, to: move.to)
        }
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
