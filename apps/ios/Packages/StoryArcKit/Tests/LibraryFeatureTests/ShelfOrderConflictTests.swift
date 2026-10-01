import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// `collections-and-reading-lists` task 7.4: a pending server reorder must not overwrite a
/// server order that has moved since the reader dragged a row. Modelled on
/// `KavitaOpenFailureTests`' mock server. Android's `ShelfOrderConflictTest` makes the same
/// claims against `KavitaSync.reorder`.
/// A plain `Bool`/`Int` box, mutated from `EntryStub`'s `@Sendable` answer closure and read
/// back on the test's own task — never from two places at once, so `@unchecked` is honest.
private final class Flag: @unchecked Sendable {
    var value = 0
}

@Suite("A stale reorder is dropped rather than sent")
struct ShelfOrderConflictTests {

    private let sourceID = "3E7F6C1C-0000-0000-0000-00000000DDDD"

    private func store(_ name: String = "storyarc-\(UUID().uuidString)") -> KavitaProgressStore {
        KavitaProgressStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    private func origin(chapter: Int = 0) -> KavitaOrigin {
        KavitaOrigin(sourceId: sourceID, libraryId: 0, seriesId: 0, volumeId: 0, chapterId: chapter)
    }

    /// @param serverOrder the chapter ids `ReadingList/items` answers with, in server order.
    private func client(host: String, serverOrder: [Int], moved: @escaping @Sendable () -> Void) throws -> KavitaClient {
        let address = try #require(KavitaAddress.from(base: "http://\(host)", apiKey: "key"))
        let items = "[" + serverOrder.enumerated().map { index, chapter in
            #"{"id":\#(chapter),"order":\#(index),"chapterId":\#(chapter),"seriesId":1,"volumeId":1,"libraryId":1}"#
        }.joined(separator: ",") + "]"
        return KavitaClient(
            address: address,
            configuration: EntryStub.session(host: host) { request in
                let path = request.url?.path() ?? ""
                if path.hasSuffix("Plugin/authenticate") {
                    return (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
                }
                if path.hasSuffix("ReadingList/items") { return (200, Data(items.utf8)) }
                if path.hasSuffix("ReadingList/update-position") {
                    moved()
                    return (200, Data("true".utf8))
                }
                return (404, Data())
            }
        )
    }

    @Test("A baseline that still matches the server is sent as planned")
    func baselineMatches() async throws {
        let moved = Flag()
        let client = try client(host: "order-matches.test", serverOrder: [1, 2, 3]) { moved.value += 1 }
        try await KavitaSync.reorderCheckingBaseline(4, to: [3, 1, 2], baseline: [1, 2, 3], onConflict: nil, through: client)
        #expect(moved.value > 0)
    }

    @Test("A server that moved since the baseline is not overwritten")
    func baselineMismatch() async throws {
        let moved = Flag()
        let conflicts = Flag()
        // The server answers 2,1,3 — it moved since this device last saw 1,2,3.
        let client = try client(host: "order-moved.test", serverOrder: [2, 1, 3]) { moved.value += 1 }
        try await KavitaSync.reorderCheckingBaseline(
            4, to: [3, 1, 2], baseline: [1, 2, 3], onConflict: { _ in conflicts.value += 1 }, through: client
        )
        #expect(moved.value == 0)
        #expect(conflicts.value == 1)
    }

    @Test("A nil baseline sends exactly as every caller did before this task")
    func nilBaselineSkipsTheCheck() async throws {
        let moved = Flag()
        let conflicts = Flag()
        let client = try client(host: "order-no-baseline.test", serverOrder: [2, 1, 3]) { moved.value += 1 }
        try await KavitaSync.reorderCheckingBaseline(
            4, to: [3, 1, 2], baseline: nil, onConflict: { _ in conflicts.value += 1 }, through: client
        )
        #expect(moved.value > 0)
        #expect(conflicts.value == 0)
    }

    @Test("A dropped order is removed from the queue through the ordinary flush")
    func flushDropsAConflictedOrder() async throws {
        let store = store()
        store.hold(KavitaUnsent(origin: origin(), page: 0, listID: 4, order: [3, 1, 2], orderBaseline: [1, 2, 3]))
        let conflicts = Flag()
        let address = try #require(KavitaAddress.from(base: "http://order-flush.test", apiKey: "key"))
        await KavitaSync.flush(
            sourceID, to: address, in: store,
            configuration: EntryStub.session(host: "order-flush.test") { request in
                let path = request.url?.path() ?? ""
                if path.hasSuffix("Plugin/authenticate") { return (200, Data(#"{"username":"ada","token":"t"}"#.utf8)) }
                if path.hasSuffix("ReadingList/items") {
                    return (200, Data(#"[{"id":2,"order":0,"chapterId":2},{"id":1,"order":1,"chapterId":1},{"id":3,"order":2,"chapterId":3}]"#.utf8))
                }
                return (404, Data())
            },
            onOrderConflict: { _ in conflicts.value += 1 }
        )
        #expect(conflicts.value == 1)
        #expect(store.unsent().isEmpty)
    }

    @Test("The first drag's baseline survives a second drag before either reaches the server")
    func baselineSurvivesASecondDrag() async {
        let store = store()
        await KavitaSync.reorder(4, to: [2, 1, 3], on: sourceID, to: nil, in: store, baseline: [1, 2, 3])
        await KavitaSync.reorder(4, to: [3, 2, 1], on: sourceID, to: nil, in: store, baseline: [2, 1, 3])

        #expect(store.unsent().first?.order == [3, 2, 1])
        #expect(store.unsent().first?.orderBaseline == [1, 2, 3])
    }
}
