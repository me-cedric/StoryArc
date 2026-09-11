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
}
