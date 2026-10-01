public import Foundation

public import Kavita
public import Persistence
internal import StoryArcCore

/// Deleting a server shelf outright, and removing one entry from inside a server reading
/// list — task 12.6. Its own file, alongside ``KavitaSyncSend`` and for the same reason:
/// `KavitaSync.swift` is at the 400-line cap this project enforces.
extension KavitaSync {
    /// Deletes a server shelf, queuing the deletion if the server is not there.
    ///
    /// `collections-and-reading-lists` treats a server shelf "as the same kind of object as
    /// locally created ones", and a local shelf can be deleted — so this is the gap. Sent
    /// through the one queue every other list edit uses, with the same confirmation local
    /// shelves take: that confirmation is the caller's, this is what it confirms.
    public static func deleteShelf(
        _ listID: Int,
        isCollection: Bool,
        on sourceId: String,
        to address: KavitaAddress?,
        in store: KavitaProgressStore,
        configuration: URLSessionConfiguration? = nil
    ) async {
        let unsent = KavitaUnsent(
            origin: KavitaOrigin(sourceId: sourceId, libraryId: 0, seriesId: 0, volumeId: 0, chapterId: 0),
            page: 0,
            listID: listID,
            deleteShelf: isCollection
        )
        guard let address else { return store.hold(unsent) }
        do {
            try await send(KavitaClient(address: address, configuration: configuration), unsent)
        } catch {
            store.hold(unsent)
        }
    }

    /// Removes one entry from a server reading list, queuing the removal if the server is
    /// not there.
    ///
    /// The same promise ``append(_:for:to:in:)`` makes in the other direction: a local list
    /// drops one entry without taking the whole list, and a server one now does too.
    public static func removeEntry(
        _ entry: KavitaReadingListItem,
        from listID: Int,
        on sourceId: String,
        to address: KavitaAddress?,
        in store: KavitaProgressStore,
        configuration: URLSessionConfiguration? = nil
    ) async {
        let unsent = KavitaUnsent(
            origin: KavitaOrigin(sourceId: sourceId, libraryId: 0, seriesId: 0, volumeId: 0, chapterId: 0),
            page: 0,
            listID: listID,
            removeItemID: entry.id,
            removeItemPosition: entry.order
        )
        guard let address else { return store.hold(unsent) }
        do {
            try await send(KavitaClient(address: address, configuration: configuration), unsent)
        } catch {
            store.hold(unsent)
        }
    }

    /// The server entries a delete on `rows` takes out of the list.
    ///
    /// `offsets` count into the drawn rows, as `onDelete` gives them. A pending row is not on
    /// the server yet, so it gives no entry to remove.
    static func leaving(
        _ offsets: IndexSet,
        of rows: [ShelfEntry],
        in items: [KavitaReadingListItem]
    ) -> [KavitaReadingListItem] {
        offsets.compactMap { index in
            guard index < rows.count, !rows[index].isPending else { return nil }
            return items.first { String($0.chapterId) == rows[index].id }
        }
    }
}
