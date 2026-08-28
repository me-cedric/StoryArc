import Foundation

public import Kavita
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
