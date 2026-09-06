import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// Reordering a server-backed reading list, and what happens to that order when the server
/// is not there.
///
/// `collections-and-reading-lists` makes the order the meaning of a reading list: "the new
/// order persists and, for a server-backed list, is sent to the server". The same
/// requirement makes an edit to a server list while the server is away "applied locally,
/// marked pending, and pushed on reconnection".
///
/// The hard claim is the last two tests: a send that fails must never cost the reader the
/// order they made. Android's `ShelfOrderTest` makes the same claims in the same order.
@Suite("Shelf order")
struct ShelfOrderTests {

    private let sourceID = "3E7F6C1C-0000-0000-0000-00000000AAAA"

    private func store(_ name: String = UUID().uuidString) -> KavitaProgressStore {
        KavitaProgressStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    private func origin(chapter: Int = 0) -> KavitaOrigin {
        KavitaOrigin(sourceId: sourceID, libraryId: 0, seriesId: 0, volumeId: 0, chapterId: chapter)
    }

    private func place(_ item: Int, _ chapter: Int) -> ShelfSync.Place {
        ShelfSync.Place(item: item, chapter: chapter)
    }

    // MARK: The moves a new order asks the server for

    @Test("An order that matches the server asks for no moves")
    func noMovesWhenAlreadyRight() {
        let places = [place(10, 1), place(11, 2), place(12, 3)]
        #expect(ShelfSync.moves(from: places, to: [1, 2, 3]).isEmpty)
    }

    @Test("An entry dragged to the top is moved from where it is to where it goes")
    func oneMoveToTheTop() {
        // Kavita's own `update-position` takes a from and a to, so the plan has to be in
        // positions rather than in identities.
        let places = [place(10, 1), place(11, 2), place(12, 3)]
        let moves = ShelfSync.moves(from: places, to: [3, 1, 2])
        #expect(moves == [ShelfSync.Move(item: 12, from: 2, to: 0)])
    }

    @Test("Each move is planned against the order the moves before it left behind")
    func movesCompose() {
        // The trap this test exists for: planning every move against the *original* order
        // sends positions the server has already invalidated, and the list ends up in an
        // order nobody asked for.
        let places = [place(10, 1), place(11, 2), place(12, 3), place(13, 4)]
        let moves = ShelfSync.moves(from: places, to: [4, 3, 2, 1])
        var current = [1, 2, 3, 4]
        for move in moves {
            let entry = current.remove(at: move.from)
            current.insert(entry, at: move.to)
        }
        #expect(current == [4, 3, 2, 1])
    }

    @Test("An entry the server no longer holds is left out of the plan rather than moved")
    func unknownEntriesAreSkipped() {
        let places = [place(10, 1), place(11, 2)]
        let moves = ShelfSync.moves(from: places, to: [99, 2, 1])
        #expect(moves == [ShelfSync.Move(item: 11, from: 1, to: 0)])
    }

    // MARK: What the reader sees while the order is waiting

    @Test("The reader's order is drawn over the server's while it waits")
    func arrangedDrawsTheWantedOrder() {
        let rows = [
            ShelfEntry(id: "1", title: "One", isPending: false),
            ShelfEntry(id: "2", title: "Two", isPending: false),
            ShelfEntry(id: "3", title: "Three", isPending: false),
        ]
        #expect(ShelfSync.arranged(rows, by: ["3", "1", "2"]).map(\.id) == ["3", "1", "2"])
    }

    @Test("An entry the wanted order does not name keeps its place at the end")
    func arrangedKeepsUnnamedEntries() {
        // The server may have gained an entry since the reorder was made. Dropping it would
        // be losing a row the reader can see.
        let rows = [
            ShelfEntry(id: "1", title: "One", isPending: false),
            ShelfEntry(id: "2", title: "Two", isPending: false),
            ShelfEntry(id: "9", title: "Nine", isPending: false),
        ]
        #expect(ShelfSync.arranged(rows, by: ["2", "1"]).map(\.id) == ["2", "1", "9"])
    }

    @Test("No wanted order leaves the server's order alone")
    func arrangedWithoutAWantedOrder() {
        let rows = [
            ShelfEntry(id: "1", title: "One", isPending: false),
            ShelfEntry(id: "2", title: "Two", isPending: false),
        ]
        #expect(ShelfSync.arranged(rows, by: []).map(\.id) == ["1", "2"])
    }

    // MARK: The order the reader made is never lost

    @Test("A reorder made with no server is written down rather than dropped")
    func reorderWithNoServerIsHeld() async {
        let store = store()
        await KavitaSync.reorder(4, to: [3, 1, 2], on: sourceID, to: nil, in: store)
        #expect(store.unsent().count == 1)
        #expect(store.unsent().first?.order == [3, 1, 2])
        #expect(store.unsent().first?.listID == 4)
    }

    @Test("A second reorder of the same list replaces the first rather than queueing beside it")
    func theLatestOrderWins() {
        let store = store()
        store.hold(KavitaUnsent(origin: origin(), page: 0, listID: 4, order: [1, 2, 3]))
        store.hold(KavitaUnsent(origin: origin(), page: 0, listID: 4, order: [3, 2, 1]))
        #expect(store.unsent().count == 1)
        #expect(store.unsent().first?.order == [3, 2, 1])
    }

    @Test("A held order and a held append for the same list are two promises, not one")
    func anOrderDoesNotDisplaceAnAppend() {
        let store = store()
        store.hold(KavitaUnsent(origin: origin(chapter: 7), page: 0, listID: 4))
        store.hold(KavitaUnsent(origin: origin(), page: 0, listID: 4, order: [7, 1]))
        #expect(store.unsent().count == 2)
    }

    @Test("A send the server refuses never loses the reader's ordering")
    func aFailedSendKeepsTheOrder() async throws {
        // The data-loss guard, and the reason the order is written down before anything is
        // sent. Port one answers nothing, which is the fastest honest "no server here".
        let store = store()
        let address = try #require(KavitaAddress.from(base: "http://127.0.0.1:1", apiKey: "k"))
        await KavitaSync.reorder(4, to: [3, 1, 2], on: sourceID, to: address, in: store)
        #expect(store.unsent().first?.order == [3, 1, 2])

        await KavitaSync.flush(sourceID, to: address, in: store)
        #expect(store.unsent().first?.order == [3, 1, 2])
    }

    @Test("A held order survives being written to disk and read back")
    func aHeldOrderIsDurable() throws {
        // Durability is the whole promise: the reader who reorders on a train has closed the
        // app long before the server is back.
        let name = UUID().uuidString
        store(name).hold(KavitaUnsent(origin: origin(), page: 0, listID: 4, order: [3, 1, 2]))
        let reopened = store(name)
        #expect(reopened.unsent().first?.order == [3, 1, 2])
    }
}
