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

    /// The server a pull is talking to, when it was given one.
    ///
    /// The two travel together because neither is any use alone here: an address says where
    /// to send, and the source says which of the queued writes belong to it.
    private struct Server {
        let id: String
        let address: KavitaAddress
    }

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
    /// A pull that finds the server *behind* sends the local position back, which is the
    /// half of `reading-progress`'s synchronisation requirement that used to be computed and
    /// dropped on the floor. Give it the server it is talking to and it goes out now; give it
    /// nothing and the position waits in the same queue a failed report waits in, because
    /// `sources` calls an unreachable server a normal state rather than a failure.
    ///
    /// Returns the conflicts, which are the only part a caller has to say anything about.
    @discardableResult
    public static func pull(
        _ chapters: [KavitaChapter],
        in kavita: KavitaProgressStore,
        into progress: ProgressStore,
        of sourceId: String? = nil,
        to address: KavitaAddress? = nil
    ) async -> [ProgressPull.Conflict] {
        var remote: [ReadingProgress] = []
        var local: [String: ReadingProgress] = [:]
        var reported: [String: KavitaChapter] = [:]
        var origins: [String: KavitaOrigin] = [:]

        for chapter in chapters where chapter.pages > 0 {
            guard let publicationId = kavita.publication(forChapter: chapter.id),
                  let held = try? await progress.progress(forStableID: publicationId)
            else { continue }
            let key = held.identity.stableID
            local[key] = held
            reported[key] = chapter
            origins[key] = kavita.origin(of: publicationId)
            // The server's position, wearing the local record's identity — which is the
            // only thing that lets the two be compared at all.
            var said = held
            said.position = KavitaExchange.position(readingTo: chapter.pagesRead, of: chapter.pages)
            said.updatedAt = Date()
            remote.append(said)
        }

        let pull = ProgressPull.merging(remote: remote) { local[$0.stableID] }
        let exchange = KavitaExchange.of(pull, against: reported)
        for record in exchange.toSave { try? await progress.save(record) }
        let server = sourceId.flatMap { id in address.map { Server(id: id, address: $0) } }
        await settle(exchange.owed, from: origins, to: server, in: kavita, into: progress)
        return pull.conflicts
    }

    /// Tells the server what the merge says it is behind on, and writes down what it took.
    ///
    /// Queued before the send is attempted rather than after it fails, for the reason
    /// ``ShelfSync/note(entry:titled:on:in:at:)`` gives: an app killed between the two has
    /// still had the reading done in it. ``flush(_:to:in:)`` is then the one push path, as it
    /// is for a reading-list edit — a second one would double every write the moment both
    /// ran.
    ///
    /// Only a position the server actually took is stamped as synchronised. One it did not
    /// stays exactly as it was and waits for the next flush, so an evening's reading offline
    /// is a queue entry rather than a lost place and never an error the reader has to read.
    private static func settle(
        _ owed: [KavitaOwed],
        from origins: [String: KavitaOrigin],
        to server: Server?,
        in kavita: KavitaProgressStore,
        into progress: ProgressStore
    ) async {
        guard !owed.isEmpty else { return }

        for each in owed {
            guard let origin = origins[each.settled.identity.stableID] else { continue }
            kavita.hold(KavitaUnsent(origin: origin, page: each.pageNum))
        }

        // No server named means there is nowhere to send and nothing more to do — the queue
        // above is the whole promise until one turns up.
        guard let server else { return }
        let delivered = Set(
            await flush(server.id, to: server.address, in: kavita)
                .filter { $0.mark == nil && $0.listID == nil }
                .map(\.origin.chapterId)
        )
        for each in owed where delivered.contains(each.chapterId) {
            try? await progress.save(each.settled)
        }
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
    ///
    /// Returns what the server took, so a caller that needs to write down the fact of the
    /// exchange can tell it apart from what is still waiting.
    @discardableResult
    public static func flush(
        _ sourceId: String,
        to address: KavitaAddress,
        in store: KavitaProgressStore
    ) async -> [KavitaUnsent] {
        let held = store.unsent().filter { $0.origin.sourceId == sourceId }
        guard !held.isEmpty else { return [] }

        let client = KavitaClient(address: address)
        var delivered: [KavitaUnsent] = []
        for each in held {
            guard (try? await send(client, each)) != nil else { continue }
            delivered.append(each)
        }
        store.sent(delivered)
        return delivered
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
