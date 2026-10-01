import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import StoryArcCore

/// Task 12.6: which server entries a delete on a server reading list's rows removes.
///
/// `KavitaListView` gives `onDelete` offsets into the rows it draws, and the server wants the
/// entry's own `readingListItemId`. ``KavitaSync/leaving(_:of:in:)`` maps one to the other.
@Suite("A delete on a server list's rows")
struct KavitaListRemovalTests {

    private func items() throws -> [KavitaReadingListItem] {
        let json = #"""
        [{"id": 501, "order": 0, "chapterId": 3103, "title": "Issue #43"},
         {"id": 502, "order": 1, "chapterId": 3104, "title": "Issue #44"}]
        """#
        return try JSONDecoder().decode([KavitaReadingListItem].self, from: Data(json.utf8))
    }

    @Test("A drawn row gives the server entry with its own item id")
    func rowGivesItsEntry() throws {
        let rows = [
            ShelfEntry(id: "3104", title: "Issue #44", isPending: false),
            ShelfEntry(id: "3103", title: "Issue #43", isPending: false),
        ]

        let leaving = KavitaSync.leaving([1], of: rows, in: try items())

        #expect(leaving.map(\.id) == [501])
    }

    @Test("A pending row gives no entry, because the server does not hold it yet")
    func pendingRowGivesNothing() throws {
        let rows = [ShelfEntry(id: "3103", title: "Issue #43", isPending: true)]

        #expect(KavitaSync.leaving([0], of: rows, in: try items()).isEmpty)
    }
}
