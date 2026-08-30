import Foundation

public import Kavita
public import StoryArcCore
public import Persistence

/// Telling a Kavita server where the reader got to.
///
/// `kavita-server` asks for the position to be sent when the reader leaves, and "retried on
/// the next successful connection if it fails". Two operations, because those are the two
/// moments: one when a chapter is closed, one when a server is reachable again.
public enum KavitaSync {

    /// Sends one position, keeping it for later if the server is not there.
    public static func report(
        _ page: Int,
        for origin: KavitaOrigin,
        to address: KavitaAddress?,
        in store: KavitaProgressStore
    ) async {
        let unsent = KavitaUnsent(origin: origin, page: page)
        guard let address else { return store.hold(unsent) }
        do {
            try await KavitaClient(address: address).report(position(origin, page))
        } catch {
            store.hold(unsent)
        }
    }

    /// Takes what the server says other devices have read, and merges it in.
    ///
    /// `reading-progress`: "progress recorded on other devices is merged into the local
    /// store". The rules are ADR-0006's and live in ``ProgressPull``; what is here is the
    /// part that only this source can do — turning a chapter's `pagesRead` into a position,
    /// and finding which publication on this device that chapter was read as.
    ///
    /// A chapter this device has never opened is skipped rather than adopted. The position
    /// is real and the publication is not: the library holds nothing to attach it to, and
    /// inventing an identity for it would be inventing a reading.
    ///
    /// Returns the conflicts, which are the only part a caller has to say anything about.
    @discardableResult
    public static func pull(
        _ chapters: [KavitaChapter],
        in kavita: KavitaProgressStore,
        into progress: ProgressStore
    ) async -> [ProgressPull.Conflict] {
        var remote: [ReadingProgress] = []
        var local: [String: ReadingProgress] = [:]

        for chapter in chapters where chapter.pages > 0 {
            guard let publicationId = kavita.publication(forChapter: chapter.id),
                  let held = try? await progress.progress(forStableID: publicationId)
            else { continue }
            local[held.identity.stableID] = held
            // The server's position, wearing the local record's identity — which is the
            // only thing that lets the two be compared at all.
            var reported = held
            reported.position = .page(index: max(0, chapter.pagesRead - 1), of: chapter.pages)
            reported.updatedAt = Date()
            remote.append(reported)
        }

        let pull = ProgressPull.merging(remote: remote) { local[$0.stableID] }
        for record in pull.toSave { try? await progress.save(record) }
        return pull.conflicts
    }

    /// Sends one deliberate mark, keeping it for later if the server is not there.
    public static func mark(
        _ isRead: Bool,
        for origin: KavitaOrigin,
        to address: KavitaAddress?,
        in store: KavitaProgressStore
    ) async {
        let unsent = KavitaUnsent(origin: origin, page: 0, mark: isRead)
        guard let address else { return store.hold(unsent) }
        do {
            try await send(KavitaClient(address: address), unsent)
        } catch {
            store.hold(unsent)
        }
    }

    /// Appends a chapter to one of the server's reading lists, holding it if the server is
    /// not there.
    public static func append(
        _ listID: Int,
        for origin: KavitaOrigin,
        to address: KavitaAddress?,
        in store: KavitaProgressStore
    ) async {
        let unsent = KavitaUnsent(origin: origin, page: 0, listID: listID)
        guard let address else { return store.hold(unsent) }
        do {
            try await send(KavitaClient(address: address), unsent)
        } catch {
            store.hold(unsent)
        }
    }

    /// Sends everything held for one server.
    ///
    /// Held positions that still fail stay held. A server that is down now was down when the
    /// chapter was read, and forgetting the position would lose exactly the reader whose
    /// connection this feature exists for.
    public static func flush(
        _ sourceId: String,
        to address: KavitaAddress,
        in store: KavitaProgressStore
    ) async {
        let held = store.unsent().filter { $0.origin.sourceId == sourceId }
        guard !held.isEmpty else { return }

        let client = KavitaClient(address: address)
        var delivered: [KavitaUnsent] = []
        for each in held {
            guard (try? await send(client, each)) != nil else { continue }
            delivered.append(each)
        }
        store.sent(delivered)
    }

    private static func send(_ client: KavitaClient, _ held: KavitaUnsent) async throws {
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
            chapterId: held.origin.chapterId,
            isRead: mark
        )
    }

    private static func position(_ origin: KavitaOrigin, _ page: Int) -> KavitaPosition {
        KavitaPosition(
            libraryId: origin.libraryId,
            seriesId: origin.seriesId,
            volumeId: origin.volumeId,
            chapterId: origin.chapterId,
            pageNum: page
        )
    }
}
