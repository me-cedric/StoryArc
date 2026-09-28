import Foundation
import Testing

import Kavita
@testable import LibraryFeature

/// Where a new shelf can be kept, and what the reader is told before it exists.
///
/// `collections-and-reading-lists`: a new shelf "is stored locally by default, or on a server
/// if the user chooses one that supports collections", and "the storage location is stated at
/// creation, not discovered later".
///
/// The second half is what makes the first half matter. A server answers the collection
/// question and the reading-list question separately, so offering a reading list to a server
/// that only holds collections would take the reader's name and their confirmation and fail
/// afterwards — the storage location discovered later, which is the thing the scenario forbids.
///
/// Android's `ShelfCreationTest` asserts these cases one for one. Neither test composes the
/// dialogue: a SwiftUI alert cannot be asked what it drew, and Robolectric never settles an
/// `OutlinedTextField` inside an `AlertDialog`.
@Suite("Shelf creation")
struct ShelfCreationTests {

    // MARK: - Fixtures

    private func page(_ name: String) -> KavitaPage {
        KavitaPage(
            id: name,
            title: name,
            address: KavitaAddress(base: URL(filePath: "/\(name)"), apiKey: "k")
        )
    }

    /// A server that holds collections, one that holds reading lists, and one that holds both.
    private var capable: ServerShelves {
        ServerShelves(
            shelves: [],
            listCapable: [page("lists"), page("both")],
            collectionCapable: [page("collections"), page("both")]
        )
    }

    // MARK: - Which servers are offered

    @Test("A reading list is offered only the servers that hold reading lists")
    func listTakesTheListCapableServers() {
        let draft = ShelfDraft(.list, from: capable)

        #expect(draft.servers.map(\.title) == ["lists", "both"])
    }

    @Test("A collection is offered only the servers that hold collections")
    func collectionTakesTheCollectionCapableServers() {
        let draft = ShelfDraft(.collection, from: capable)

        #expect(draft.servers.map(\.title) == ["collections", "both"])
    }

    @Test("The two kinds are offered different servers, which is the point of asking twice")
    func theTwoKindsDiffer() {
        // Without this the two cases above would both pass against one shared list.
        let lists = ShelfDraft(.list, from: capable).servers.map(\.title)
        let collections = ShelfDraft(.collection, from: capable).servers.map(\.title)

        #expect(lists != collections)
    }

    // MARK: - What the reader is told

    @Test("With no server to offer, the shelf is stated as kept on this device")
    func noServerMeansThisDevice() {
        let nothing = ServerShelves(shelves: [], listCapable: [], collectionCapable: [])

        #expect(ShelfDraft(.collection, from: nothing).isKeptOnThisDevice)
    }

    @Test("With a server to offer, confirming is a choice rather than the only place")
    func aServerMeansAChoice() {
        #expect(ShelfDraft(.collection, from: capable).isKeptOnThisDevice == false)
    }

    @Test("A kind with no capable server says so while the other kind has one")
    func theStatementIsPerKind() {
        // The reader making a reading list on a collections-only server is told it stays
        // here, because it does. The same app, the same moment, the other kind: a choice.
        let collectionsOnly = ServerShelves(
            shelves: [],
            listCapable: [],
            collectionCapable: [page("collections")]
        )

        #expect(ShelfDraft(.list, from: collectionsOnly).isKeptOnThisDevice)
        #expect(ShelfDraft(.collection, from: collectionsOnly).isKeptOnThisDevice == false)
    }
}
