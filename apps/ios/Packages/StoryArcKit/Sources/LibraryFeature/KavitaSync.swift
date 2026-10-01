public import Foundation

public import Kavita
public import StoryArcCore
public import Persistence

/// A conflict a pull found, named for the reader rather than left as bare positions.
///
/// `reading-progress` asks the notice to name what changed. `ProgressPull.Conflict` alone
/// has no title -- only the chapter a pull is still holding when it builds this does.
public struct KavitaConflict: Sendable, Equatable {
    public let title: String
    public let resolved: ReadingProgress
    public let discarded: ReadingPosition
}

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
        /// The session a test answers through. Nil in the app.
        let configuration: URLSessionConfiguration?
    }

    /// Sends one position, keeping it for later if the server is not there.
    ///
    /// A success drops any position held earlier for the same chapter: this report is the
    /// truth for it now, and an older held page left in the queue would be the next flush's
    /// to send, moving the server back to where the reader was before this session.
    public static func report(
        _ page: Int,
        for origin: KavitaOrigin,
        to address: KavitaAddress?,
        in store: KavitaProgressStore,
        progress: ProgressStore? = nil,
        configuration: URLSessionConfiguration? = nil
    ) async {
        let unsent = KavitaUnsent(origin: origin, page: page)
        guard let address else { return store.hold(unsent) }
        do {
            try await KavitaClient(address: address, configuration: configuration)
                .report(position(origin, page))
            store.drop(unsent.key)
            await stampSynced(chapterId: origin.chapterId, in: store, into: progress)
        } catch {
            store.hold(unsent)
        }
    }

    /// Marks the local record for a reported chapter as synchronised, so the next pull's
    /// merge sees it as untouched rather than as "changed since last sync".
    ///
    /// Silent when there is no local record — a position can be reported for a chapter
    /// this device opened once and no longer holds, and there is nothing to stamp.
    private static func stampSynced(
        chapterId: Int,
        in store: KavitaProgressStore,
        into progress: ProgressStore?
    ) async {
        guard let progress,
              let publicationId = store.publication(forChapter: chapterId),
              let existing = try? await progress.progress(forStableID: publicationId)
        else { return }
        try? await progress.save(KavitaExchange.settled(existing))
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
        to address: KavitaAddress? = nil,
        configuration: URLSessionConfiguration? = nil
    ) async -> [KavitaConflict] {
        var remote: [ReadingProgress] = []
        var local: [String: ReadingProgress] = [:]
        var reported: [String: KavitaChapter] = [:]
        var origins: [String: KavitaOrigin] = [:]

        for chapter in chapters where chapter.pages > 0 {
            let publicationId = kavita.publication(forChapter: chapter.id)
            let origin = publicationId.flatMap { kavita.origin(of: $0) }
            // The server's own identifier first, because it finds the record wherever the
            // chapter's bytes ended up. The stable id is the fallback, and the only route
            // for a record written before any server identifier was built.
            var found: ReadingProgress?
            if let server = origin?.serverIdentifier {
                found = try? await progress.progress(
                    for: PublicationIdentity(serverIdentifier: server)
                )
            }
            if found == nil, let publicationId {
                found = try? await progress.progress(forStableID: publicationId)
            }
            // A chapter the browser never opened has no remembered origin to build a
            // server identifier from — but the library row the source's own refresh
            // already contributed carries one, built the very same way, straight from
            // this source and this chapter. Filing under it here is what lets that row's
            // own reading merge in without the reader ever opening the browser.
            if found == nil, let sourceId, let sourceUUID = UUID(uuidString: sourceId) {
                let server = PublicationIdentity.ServerIdentifier(
                    sourceID: sourceUUID, remoteID: "chapter:\(chapter.id)"
                )
                found = try? await progress.progress(for: PublicationIdentity(serverIdentifier: server))
            }
            guard let held = found else { continue }
            let key = held.identity.stableID
            local[key] = held
            reported[key] = chapter
            if let origin { origins[key] = origin }
            // The server's position, wearing the local record's identity — which is the
            // only thing that lets the two be compared at all.
            var said = held
            said.position = KavitaExchange.position(
                readingTo: chapter.pagesRead, of: chapter.pages, like: held.position
            )
            // The server's own finished state, not the local record's copied forward.
            // Copying it forward is the defect: the merge's finished rule (either side
            // finished wins) never saw a server that had finished a chapter this device
            // had not, because `said` carried `held.isFinished` unchanged.
            let wasFinished = said.isFinished
            said.isFinished = chapter.isFinished
            if chapter.isFinished, !wasFinished { said.finishedAt = Date() }
            said.updatedAt = Date()
            remote.append(said)
        }

        let pull = ProgressPull.merging(remote: remote) { local[$0.stableID] }
        let exchange = KavitaExchange.of(pull, against: reported)
        for record in exchange.toSave { try? await progress.save(record) }
        var server: Server?
        if let sourceId, let address { server = Server(id: sourceId, address: address, configuration: configuration) }
        await settle(exchange.owed, from: origins, to: server, in: kavita, into: progress)
        return pull.conflicts.map { conflict in
            KavitaConflict(
                title: reported[conflict.resolved.identity.stableID]?.displayName ?? "",
                resolved: conflict.resolved,
                discarded: conflict.discarded
            )
        }
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
    ///
    /// The flush runs when nothing is owed too: a pull that reached its server is the "next
    /// successful connection" `kavita-server` retries a held write on.
    private static func settle(
        _ owed: [KavitaOwed],
        from origins: [String: KavitaOrigin],
        to server: Server?,
        in kavita: KavitaProgressStore,
        into progress: ProgressStore
    ) async {
        // A finished record is owed a mark, not a page — see `KavitaOwed.isMarkRead`.
        func unsent(for each: KavitaOwed, origin: KavitaOrigin) -> KavitaUnsent {
            each.isMarkRead
                ? KavitaUnsent(origin: origin, page: 0, mark: true)
                : KavitaUnsent(origin: origin, page: each.pageNum)
        }

        for each in owed {
            guard let origin = origins[each.settled.identity.stableID] else { continue }
            kavita.hold(unsent(for: each, origin: origin))
        }

        // No server named means there is nowhere to send and nothing more to do — the queue
        // above is the whole promise until one turns up.
        guard let server else { return }
        let deliveredKeys = Set(
            await flush(server.id, to: server.address, in: kavita, configuration: server.configuration).map(\.key)
        )
        for each in owed {
            guard let origin = origins[each.settled.identity.stableID],
                  deliveredKeys.contains(unsent(for: each, origin: origin).key)
            else { continue }
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

    /// Records the order a reader gave a server reading list, then tries to send it.
    ///
    /// Written down before anything is sent, which is the opposite way round from a position
    /// and deliberately so: `collections-and-reading-lists` makes a reading list's order its
    /// meaning, and a send that failed after the reader had dragged a row would cost them
    /// the one thing the list is for. The record is what the list is drawn from until the
    /// server takes it, so a refused send is a queue entry rather than a lost order.
    ///
    /// The send is ``flush(_:to:in:)`` rather than a call of its own, for the reason
    /// ``ShelfSync`` gives: one push path, or every write goes twice the moment both run.
    public static func reorder(
        _ listID: Int,
        to order: [Int],
        on sourceId: String,
        to address: KavitaAddress?,
        in store: KavitaProgressStore,
        /// The server order this device had seen, read by the caller before this move was
        /// applied locally. Nil skips task 7.4's check. Ignored when an order is already
        /// held for this list — the earlier hold's own baseline is what a later send is
        /// still checked against, so a second drag before the first reaches the server does
        /// not quietly widen what counts as unchanged.
        baseline: [Int]? = nil,
        onOrderConflict: (@Sendable (Int) -> Void)? = nil
    ) async {
        let key = "order:\(sourceId):\(listID)"
        let held = store.unsent().first { $0.key == key }
        store.hold(
            KavitaUnsent(
                origin: KavitaOrigin(
                    sourceId: sourceId,
                    libraryId: 0,
                    seriesId: 0,
                    volumeId: 0,
                    chapterId: 0
                ),
                page: 0,
                listID: listID,
                order: order,
                orderBaseline: held?.orderBaseline ?? baseline
            )
        )
        guard let address else { return }
        await flush(sourceId, to: address, in: store, onOrderConflict: onOrderConflict)
    }

    /// The order this device is still waiting to give one of a server's reading lists.
    ///
    /// Read by the screen that draws the list, so what the reader sees is the order they
    /// made rather than the one the server has not been told about yet.
    public static func wantedOrder(
        of listID: Int,
        on sourceId: String,
        in store: KavitaProgressStore
    ) -> [Int] {
        store.unsent()
            .first { $0.origin.sourceId == sourceId && $0.listID == listID && $0.order != nil }?
            .order ?? []
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
        in store: KavitaProgressStore,
        progress: ProgressStore? = nil,
        configuration: URLSessionConfiguration? = nil,
        /// Task 7.4: told when a held order was dropped as stale rather than sent.
        onOrderConflict: (@Sendable (Int) -> Void)? = nil
    ) async -> [KavitaUnsent] {
        let held = store.unsent().filter { $0.origin.sourceId == sourceId }
        guard !held.isEmpty else { return [] }

        let client = KavitaClient(address: address, configuration: configuration)
        var delivered: [KavitaUnsent] = []
        for each in held {
            guard (try? await send(client, each, onOrderConflict: onOrderConflict)) != nil else { continue }
            delivered.append(each)
        }
        store.sent(delivered)
        // A plain position, not a mark or a list write — the only kind of held item a
        // local record has anything to say about.
        for each in delivered where each.mark == nil && each.listID == nil {
            await stampSynced(chapterId: each.origin.chapterId, in: store, into: progress)
        }
        return delivered
    }

    private static func send(
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
