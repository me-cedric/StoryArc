import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// `collections-and-reading-lists` task 7.6: `KavitaListView` used to draw a pending row
/// only when its caller remembered to pass `pending:` — `HomeShelvesRow` did not, so a list
/// opened from Home hid every edit made while the server was away. `rows` now reads
/// `ShelfEditStore()` itself, the way Android's `KavitaListScreen` already does, so every
/// entry point agrees.
/// `.serialized`: both tests write to `ShelfEditStore()`'s one `UserDefaults.standard` blob,
/// the same store `KavitaListView.pending` reads — there is no injection seam for it, the
/// same as production's own `ShelfEditStore()` calls.
@MainActor
@Suite("A server list's pending rows do not depend on who opened it", .serialized)
struct KavitaListPendingTests {

    private static let local = URL(string: "http://localhost:1") ?? URL(filePath: "/")

    private func view(server: String, list: Int) -> KavitaListView {
        KavitaListView(
            server: KavitaPage(id: server, title: "Attic", address: KavitaAddress(base: Self.local, apiKey: "k")),
            listID: list,
            title: "Crossover",
            onOpen: { _, _ in }
        )
    }

    @Test("A pending edit shows as a row with no items fetched, and no pending: argument given")
    func pendingRowSurvivesWithNoCaller() throws {
        let server = UUID().uuidString
        let shelf = ShelfKey(sourceID: server, shelfID: 9)
        let edit = ShelfEdit(shelf: shelf, entry: "41", title: "Issue #41", madeAt: Date())
        let store = ShelfEditStore()
        store.update { $0.queueing(edit) }
        defer { store.update { $0.dropping([edit]) } }

        let rows = view(server: server, list: 9).rows

        #expect(rows.contains { $0.id == "41" && $0.isPending })
    }

    @Test("A pending edit for a different list is not drawn on this one")
    func pendingIsScopedToItsOwnList() throws {
        let server = UUID().uuidString
        let elsewhere = ShelfKey(sourceID: server, shelfID: 10)
        let edit = ShelfEdit(shelf: elsewhere, entry: "41", title: "Issue #41", madeAt: Date())
        let store = ShelfEditStore()
        store.update { $0.queueing(edit) }
        defer { store.update { $0.dropping([edit]) } }

        let rows = view(server: server, list: 9).rows

        #expect(rows.isEmpty)
    }
}
