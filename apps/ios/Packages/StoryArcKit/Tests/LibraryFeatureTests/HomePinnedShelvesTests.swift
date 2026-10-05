import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The shelves a reader pinned, as the home surface draws them.
///
/// `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the home
/// surface as a shelf of its own". A server's shelf is one of those —
/// `collections-and-reading-lists` calls it "the same kind of object as locally created
/// ones" — and it has to reach the surface without a request, because *The home surface
/// never waits on a source* forbids one.
///
/// Android's `HomePinnedShelvesTest` asserts the same five cases.
@Suite("Pinned shelves on the home surface")
struct HomePinnedShelvesTests {

    private let source = UUID()

    private func local(_ title: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            origin: .embedded
        )
    }

    private func chapter(_ title: String, _ id: Int) -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: PublicationIdentity.ServerIdentifier(
                    sourceID: source,
                    remoteID: "chapter:\(id)"
                )
            ),
            format: .cbz,
            displayTitle: title,
            origin: .embedded,
            sourceID: source
        )
    }

    private func serverShelf(_ title: String, _ id: Int) -> RememberedShelf {
        RememberedShelf(kind: .readingList, sourceID: source, serverID: id, title: title)
    }

    @Test("A pinned server reading list is a shelf of its own")
    func aPinnedServerList() {
        let shelf = serverShelf("Crossover", 7)
        let rows = pinnedShelfRows(
            PinnedShelves().toggling(shelf.pin),
            shelves: Shelves(),
            remembered: [shelf],
            members: { _ in ["11", "12"] },
            publications: [chapter("Second", 12), chapter("First", 11)]
        )

        #expect(rows.map(\.name) == ["Crossover"])
        // The server's own order, which is the record `ShelfSync` kept — not the order the
        // library happens to hold the chapters in.
        #expect(rows[0].publications.map(\.displayTitle) == ["First", "Second"])
    }

    @Test("A server shelf nobody pinned is not a shelf of its own")
    func anUnpinnedServerList() {
        let shelf = serverShelf("Crossover", 7)
        let rows = pinnedShelfRows(
            PinnedShelves(),
            shelves: Shelves(),
            remembered: [shelf],
            members: { _ in ["11"] },
            publications: [chapter("First", 11)]
        )

        #expect(rows.isEmpty)
    }

    @Test("A pinned server shelf this device holds nothing of is absent, not an empty heading")
    func nothingToDraw() {
        // *A shelf that would be empty*: a heading over no covers would be the surface
        // waiting on something, which is the one thing it must never look like it is doing.
        let shelf = serverShelf("Crossover", 7)
        let rows = pinnedShelfRows(
            PinnedShelves().toggling(shelf.pin),
            shelves: Shelves(),
            remembered: [shelf],
            members: { _ in ["99"] },
            publications: [chapter("First", 11)]
        )

        #expect(rows.isEmpty)
    }

    @Test("The membership comes from the record, never from a server")
    func theRecordIsTheOnlySource() {
        // Nothing is asked: with no record there is no shelf, rather than a request.
        let shelf = serverShelf("Crossover", 7)
        var asked: [ShelfKey] = []
        let rows = pinnedShelfRows(
            PinnedShelves().toggling(shelf.pin),
            shelves: Shelves(),
            remembered: [shelf],
            members: { key in
                asked.append(key)
                return nil
            },
            publications: [chapter("First", 11)]
        )

        #expect(rows.isEmpty)
        #expect(asked == [ShelfKey(sourceID: source.uuidString, shelfID: 7)])
    }

    @Test("A pinned server collection never borrows a reading list's members")
    func aCollectionIsNeverAsked() {
        // ``ShelfKey`` names a source and a number and not a kind, and a Kavita server
        // numbers its collections and its reading lists from one apiece. Seen on a simulator
        // on 2026-10-05: a pinned *Staff picks* drew *Start here*'s three covers.
        let collection = RememberedShelf(kind: .collection, sourceID: source, serverID: 7, title: "Staff picks")
        var asked = false
        let rows = pinnedShelfRows(
            PinnedShelves().toggling(collection.pin),
            shelves: Shelves(),
            remembered: [collection],
            members: { _ in
                asked = true
                return ["11"]
            },
            publications: [chapter("First", 11)]
        )

        #expect(rows.isEmpty)
        #expect(!asked)
    }

    @Test("The reader's own shelves come first, and a server's after them")
    func theOrderOfTheThreeKinds() {
        let collection = PublicationCollection(name: "Mine", members: ["path:/One"])
        let shelf = serverShelf("Theirs", 7)
        let rows = pinnedShelfRows(
            PinnedShelves().toggling(shelf.pin).toggling(.collection(collection.id)),
            shelves: Shelves(collections: [collection]),
            remembered: [shelf],
            members: { _ in ["11"] },
            publications: [local("One"), chapter("First", 11)]
        )

        #expect(rows.map(\.name) == ["Mine", "Theirs"])
    }
}
