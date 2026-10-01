internal import Foundation

internal import Kavita
internal import Persistence

/// What one held write actually sends, by the kind of thing it is.
///
/// Its own file, split from `KavitaSync.swift` when that file passed the 400-line cap this
/// project enforces: `flush` and `mark` both call this, and neither needed to carry it.
extension KavitaSync {
    static func send(
        _ client: KavitaClient,
        _ held: KavitaUnsent,
        onOrderConflict: (@Sendable (Int) -> Void)? = nil
    ) async throws {
        if let listID = held.listID, let order = held.order {
            return try await reorderCheckingBaseline(
                listID,
                to: order,
                baseline: held.orderBaseline,
                onConflict: onOrderConflict,
                through: client
            )
        }
        if let listID = held.listID {
            return try await client.append(
                toList: listID,
                seriesId: held.origin.seriesId,
                chapterIds: [held.origin.chapterId]
            )
        }
        guard let mark = held.mark else {
            return try await client.report(position(held.origin, held.page))
        }
        try await client.mark(
            seriesId: held.origin.seriesId,
            volumeId: held.origin.volumeId,
            chapterId: held.origin.chapterId,
            isRead: mark
        )
    }

    static func position(_ origin: KavitaOrigin, _ page: Int) -> KavitaPosition {
        KavitaPosition(
            libraryId: origin.libraryId,
            seriesId: origin.seriesId,
            volumeId: origin.volumeId,
            chapterId: origin.chapterId,
            pageNum: page
        )
    }
}
