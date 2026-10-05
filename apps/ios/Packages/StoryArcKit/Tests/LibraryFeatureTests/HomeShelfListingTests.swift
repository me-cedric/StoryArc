import Foundation
import Testing

@testable import Kavita
@testable import LibraryFeature
@testable import StoryArcCore

/// The two shelves the home surface lists the reader's curation on.
///
/// `collections-and-reading-lists`, *Shelves on the home surface*. Every claim here is one the
/// assembly can be asked about without a screen: which half a shelf lands in, what a card
/// says, which shelves are left out, and what a fetch is written down as.
///
/// Case for case with Android's `HomeShelfListingTest`.
@Suite("Home shelf listing")
struct HomeShelfListingTests {

    /// One source, fixed for the life of a test case, so a remembered shelf can name it.
    private let serverID = UUID()

    private func issue(_ name: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/\(name).cbz"),
            format: .cbz,
            displayTitle: name,
            origin: .inferred
        )
    }

    private var library: [Publication] {
        [issue("one"), issue("two"), issue("three"), issue("four")]
    }

    private func collection(_ name: String, members: Int = 0) -> PublicationCollection {
        PublicationCollection(name: name, members: Set(library.prefix(members).map(\.id)))
    }

    private func list(_ name: String, entries: Int = 0) -> ReadingList {
        ReadingList(name: name, entries: library.prefix(entries).map(\.id))
    }

    @Test("A collection lands on the collections shelf and a list on its own")
    func twoHalves() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [collection("Image")], lists: [list("Crisis")]),
            publications: library
        )

        #expect(listing.collections.map(\.name) == ["Image"])
        #expect(listing.lists.map(\.name) == ["Crisis"])
        #expect(!listing.isEmpty)
    }

    @Test("Neither half holds anything for a reader with no shelves")
    func nothingAtAll() {
        let listing = HomeShelfIndex.assemble(shelves: Shelves(), publications: library)

        #expect(listing.isEmpty)
        #expect(listing.collections.isEmpty)
        #expect(listing.lists.isEmpty)
    }

    @Test("One kind with nothing in it leaves the other alone")
    func oneKindOnly() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [collection("Image", members: 2)]),
            publications: library
        )

        #expect(listing.collections.count == 1)
        #expect(listing.lists.isEmpty)
        #expect(!listing.isEmpty)
    }

    @Test("A reading list has a position and a collection has none")
    func onlyAListHasAPosition() {
        let shelves = Shelves(
            collections: [collection("Image", members: 4)],
            lists: [list("Crisis", entries: 4)]
        )
        let listing = HomeShelfIndex.assemble(
            shelves: shelves,
            publications: library,
            finished: Set(library.prefix(2).map(\.id))
        )

        #expect(listing.collections[0].progress == nil)
        #expect(listing.lists[0].progress?.fraction == 0.5)
    }

    @Test("A shelf stands on the first four covers it holds")
    func fourTiles() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [collection("Image", members: 4)]),
            publications: library
        )

        #expect(listing.collections[0].tiles.count == 4)
    }

    @Test("A shelf with nothing in it has no tiles and still appears")
    func anEmptyShelfIsStillAShelf() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [collection("Empty")]),
            publications: library
        )

        #expect(listing.collections[0].name == "Empty")
        // swiftlint:disable:next empty_count
        #expect(listing.collections[0].count == 0)
        #expect(listing.collections[0].tiles.isEmpty)
    }

    @Test("A remembered shelf is listed and labelled with its source")
    func aRememberedShelfIsListed() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(),
            publications: library,
            remembered: [
                RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "Marvel"),
                RememberedShelf(
                    kind: .readingList,
                    sourceID: serverID,
                    serverID: 9,
                    title: "Crisis, in order"
                )
            ],
            openableSources: [serverID: "Kavita at home"]
        )

        #expect(listing.collections.map(\.name) == ["Marvel"])
        #expect(listing.lists.map(\.name) == ["Crisis, in order"])
        #expect(listing.collections[0].sourceName == "Kavita at home")
    }

    @Test("A remembered shelf states no count, because this device does not know one")
    func noCountForARememberedShelf() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(),
            publications: library,
            remembered: [
                RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "Marvel")
            ],
            openableSources: [serverID: "Kavita at home"]
        )

        #expect(listing.collections[0].count == nil)
    }

    @Test("A remembered shelf draws the count and finished position it has cached")
    func cachedCountAndFinishedAreDrawn() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(),
            publications: library,
            remembered: [
                RememberedShelf(
                    kind: .readingList, sourceID: serverID, serverID: 9, title: "Crisis, in order",
                    count: 12, finished: 5
                )
            ],
            openableSources: [serverID: "Kavita at home"]
        )

        #expect(listing.lists[0].count == 12)
        #expect(listing.lists[0].finished == 5)
    }

    @Test("A remembered shelf whose source has gone is left out")
    func aSourceThatWasRemoved() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [collection("Mine")]),
            publications: library,
            remembered: [
                RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "Marvel")
            ],
            openableSources: [:]
        )

        #expect(listing.collections.map(\.name) == ["Mine"])
    }

    @Test("The reader's own shelves lead a half, and pinned ones lead them")
    func pinnedFirst() {
        let first = collection("First")
        let second = collection("Second")
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [first, second]),
            publications: library,
            remembered: [
                RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "Marvel")
            ],
            openableSources: [serverID: "Kavita at home"],
            pinned: PinnedShelves().toggling(.collection(second.id))
        )

        #expect(listing.collections.map(\.name) == ["Second", "First", "Marvel"])
    }

    @Test("A pinned server shelf leads the half, ahead of the reader's own unpinned ones")
    func aPinnedServerShelfLeads() {
        // `collections-and-reading-lists`: a server's shelf is "the same kind of object as
        // locally created ones", so `home-screen`'s "ahead of the unpinned ones" reaches
        // across the join. It used to stop at it — every server shelf sat behind every local
        // one, whatever the reader pinned.
        let marvel = RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "Marvel")
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(collections: [collection("First"), collection("Second")]),
            publications: library,
            remembered: [marvel],
            openableSources: [serverID: "Kavita at home"],
            pinned: PinnedShelves().toggling(marvel.pin)
        )

        #expect(listing.collections.map(\.name) == ["Marvel", "First", "Second"])
    }

    @Test("Every card's key is its own")
    func keysAreUnique() {
        let listing = HomeShelfIndex.assemble(
            shelves: Shelves(
                collections: [collection("A"), collection("B")],
                lists: [list("C")]
            ),
            publications: library,
            remembered: [
                RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "D")
            ],
            openableSources: [serverID: "Kavita at home"]
        )

        let keys = (listing.collections + listing.lists).map(\.id)
        #expect(Set(keys).count == keys.count)
    }

    private func fetched(_ id: Int, _ title: String, isList: Bool) -> ServerShelf {
        ServerShelf(
            server: KavitaPage(
                id: serverID.uuidString,
                title: "Kavita at home",
                address: KavitaAddress(base: URL(filePath: "/k"), apiKey: "key")
            ),
            id: id,
            title: title,
            isList: isList
        )
    }

    @Test("What a fetch found becomes the record, both kinds")
    func theRecordOfAFetch() {
        let record = HomeShelfIndex.remembering([
            fetched(4, "Marvel", isList: false),
            fetched(5, "Image", isList: false),
            fetched(9, "Crisis, in order", isList: true)
        ])

        #expect(record.count == 3)
        let read = record
        #expect(read.map(\.title).sorted() == ["Crisis, in order", "Image", "Marvel"])
        #expect(Set(read.map(\.kind)) == [.collection, .readingList])
    }

    /// The record is what a fetch found, not what it has ever found. A shelf deleted on the
    /// server leaves, which a merge would never let it do.
    @Test("A later fetch that finds one shelf writes one shelf")
    func theRecordIsReplaced() {
        let first = HomeShelfIndex.remembering([
            fetched(4, "Marvel", isList: false),
            fetched(5, "Image", isList: false)
        ])
        let second = HomeShelfIndex.remembering([fetched(5, "Image", isList: false)])

        #expect(first.count == 2)
        #expect(second.count == 1)
        #expect(second.first?.title == "Image")
    }

    /// A visit to the shelves screen rewrites the record. The counts the home cards cached
    /// must survive that, or the next launch draws no count again.
    @Test("A later fetch keeps the count a home card cached for a shelf that is still there")
    func aFetchKeepsTheCachedCount() {
        let first = HomeShelfIndex.remembering([
            fetched(4, "Marvel", isList: false),
            fetched(9, "Crisis, in order", isList: true)
        ])
        let cached = first.map { $0.kind == .readingList ? $0.counted(12, finished: 5) : $0 }
        let second = HomeShelfIndex.remembering(
            [fetched(9, "Crisis, in order", isList: true), fetched(6, "New", isList: false)],
            previous: cached
        )

        let list = second.first { $0.serverID == 9 }
        #expect(list?.count == 12)
        #expect(list?.finished == 5)
        #expect(second.first { $0.serverID == 6 }?.count == nil)
    }

    private func entry(read: Int, of total: Int) throws -> KavitaReadingListItem {
        let json = #"{"id":1,"order":0,"seriesId":1,"chapterId":1,"pagesRead":\#(read),"pagesTotal":\#(total)}"#
        return try JSONDecoder().decode(KavitaReadingListItem.self, from: Data(json.utf8))
    }

    @Test("A list's card counts every entry, and the entries the server reports as finished")
    func aListIsCounted() throws {
        let shelf = RememberedShelf(kind: .readingList, sourceID: serverID, serverID: 9, title: "Crisis")
        let counted = shelf.counted(
            items: [try entry(read: 20, of: 20), try entry(read: 3, of: 20), try entry(read: 0, of: 20)]
        )

        #expect(counted.count == 3)
        #expect(counted.finished == 1)
        #expect(counted.id == shelf.id)
    }

    @Test("A collection's card counts its series and states no position")
    func aCollectionIsCounted() {
        let shelf = RememberedShelf(kind: .collection, sourceID: serverID, serverID: 4, title: "Marvel")
        let counted = shelf.counted(series: [7, 3].map { KavitaSeries(id: $0, name: "S\($0)", libraryId: 1) })

        #expect(counted.count == 2)
        #expect(counted.finished == nil)
    }
}
