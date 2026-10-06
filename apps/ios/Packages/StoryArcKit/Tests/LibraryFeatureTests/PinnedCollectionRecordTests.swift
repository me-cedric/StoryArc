import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import StoryArcCore

/// `close-the-audited-gaps` task 17.10: a pinned server collection is a Home shelf of its own.
///
/// Two of the three things it rests on had no test: a collection's key carries the collection
/// kind, and its record lists the names of its series. Reverted, either one emptied every
/// pinned collection on Home while every other test stayed green, because the home tests hand
/// the shelf its members rather than reading the record.
@Suite("A pinned server collection is recorded as one")
struct PinnedCollectionRecordTests {

    private let server = KavitaPage(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!.uuidString,
        title: "Kavita at home",
        address: KavitaAddress(base: URL(filePath: "/k"), apiKey: "key")
    )

    @Test("Collection 7 and reading list 7 on one server are two shelves")
    func eachKindHasItsOwnKey() {
        let collection = ServerShelf(server: server, id: 7, title: "Arcs", isList: false)
        let list = ServerShelf(server: server, id: 7, title: "Arcs", isList: true)

        #expect(ShelfSync.key(collection).kind == .collection)
        #expect(ShelfSync.key(list).kind == .readingList)
        #expect(ShelfSync.key(collection) != ShelfSync.key(list))
    }

    @Test("A collection records the names of its series, which is what Home filters by")
    func aCollectionRecordsSeriesNames() {
        let series = [
            KavitaSeries(id: 3, name: "Ashfall", libraryId: 1),
            KavitaSeries(id: 9, name: "Tidal Reach", libraryId: 1),
        ]

        #expect(ShelfSync.collectionMembers(series) == ["Ashfall", "Tidal Reach"])
    }
}
