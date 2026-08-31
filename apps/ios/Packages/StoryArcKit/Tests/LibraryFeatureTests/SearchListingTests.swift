import Foundation
import Testing

@testable import LibraryFeature
@testable import StoryArcCore

/// The one-search merge, asserted against the same table as Android's `SearchListingTest`.
///
/// `library-browsing` asks for local results now and remote results later, merged into one
/// ranked list with each row labelled, and without disturbing what the reader is already
/// looking at. That promise is a property of this value and of nothing else, so it is
/// asserted here — case for case on both platforms, per ADR-0001. Add a case here, add it
/// there.
@Suite("Search listing")
struct SearchListingTests {

    private static let folder = SearchOrigin.library(id: "folder", name: "Attic NAS")
    private static let server = SearchOrigin.library(id: "server", name: "Reading Room")

    private func held(
        _ title: String,
        kind: MatchKind = .publication,
        in origin: SearchOrigin = SearchListingTests.folder,
        id: String? = nil
    ) -> FoundRow {
        FoundRow(
            result: SearchResult(kind: kind, title: title, publicationID: id ?? title),
            origin: origin
        )
    }

    private func away(
        _ title: String,
        kind: MatchKind = .publication,
        in origin: SearchOrigin = SearchListingTests.server
    ) -> FoundRow {
        FoundRow(
            result: SearchResult(
                kind: kind,
                title: title,
                route: SearchRoute(sourceID: origin.key, key: title)
            ),
            origin: origin
        )
    }

    /// What the reader actually sees: the groups, one after another.
    private func rendered(_ listing: SearchListing) -> [String] {
        listing.groups.flatMap { $0.rows }.map(\.result.title)
    }

    @Test("What the device holds is the whole answer until something else replies")
    func localIsInstant() {
        let listing = SearchListing(term: "bone", local: [held("Bone")], asking: ["server"])
        #expect(listing.rows.map(\.result.title) == ["Bone"])
        #expect(listing.isWaiting)
    }

    @Test("A late answer lands under what is already there, and moves nothing")
    func remoteAppends() {
        let before = SearchListing(term: "bone", local: [held("Carbone")], asking: ["server"])
        let after = before.answered("server", with: [away("Bone")])
        // The server's row answers better and still goes underneath: the promise that
        // nothing already on screen moves outranks the ranking itself.
        #expect(after.rows.map(\.result.title) == ["Carbone", "Bone"])
        #expect(!after.isWaiting)
    }

    @Test("One answer is ranked within itself before it is appended")
    func answersAreRankedWithinThemselves() {
        let listing = SearchListing(term: "bone", asking: ["server"])
            .answered("server", with: [away("Carbone"), away("Bone Up"), away("Bone")])
        #expect(listing.rows.map(\.result.title) == ["Bone", "Bone Up", "Carbone"])
    }

    @Test("The device's own answer is ranked by the same rule")
    func localIsRankedToo() {
        let listing = SearchListing(term: "bone", local: [held("Carbone"), held("Bone")])
        #expect(listing.rows.map(\.result.title) == ["Bone", "Carbone"])
    }

    @Test("Two libraries that both hold a book are two labelled rows")
    func noCrossLibraryFold() {
        // The photographed defect. A catalogue served exactly one match, the device held a
        // book of the same title, and the catalogue's answer never reached the screen.
        let listing = SearchListing(term: "fine print", local: [held("Fine Print")])
            .answered("server", with: [away("Fine Print")])
        #expect(listing.rows.count == 2)
        #expect(listing.rows.map(\.origin) == [Self.folder, Self.server])
    }

    @Test("A library that says the same thing twice is folded into one row")
    func foldsWithinOneLibrary() {
        let listing = SearchListing(term: "bone", asking: ["server"])
            .answered("server", with: [away("Bone"), away("Bone")])
        #expect(listing.rows.count == 1)
    }

    @Test("A server's copy of a book downloaded from that same server folds away")
    func foldsTheServersCopyOfItsOwnDownload() {
        // A chapter fetched from a library carries that library's identity, so the copy on
        // the device and the copy on the server are one row — the one that opens on a plane.
        let listing = SearchListing(term: "bone", local: [held("Bone", in: Self.server)])
            .answered("server", with: [away("Bone")])
        #expect(listing.rows.count == 1)
        #expect(listing.rows[0].result.publicationID == "Bone")
    }

    @Test("Two books of one title in one library are two books")
    func neverFoldsWhatTheDeviceHolds() {
        let listing = SearchListing(
            term: "bone",
            local: [held("Bone", id: "one"), held("Bone", id: "two")]
        )
        #expect(listing.rows.count == 2)
    }

    @Test("A heading appears in the order its first row did")
    func headingsFollowTheRows() {
        let listing = SearchListing(term: "bone", local: [held("Carbone")], asking: ["server"])
            .answered("server", with: [away("Bone", kind: .series)])
        #expect(listing.groups.map(\.kind) == [.publication, .series])
        #expect(listing.groups.map { $0.rows.count } == [1, 1])
    }

    @Test("A library that could not answer is named once, however often it is asked")
    func silentOnce() {
        let listing = SearchListing(term: "bone", asking: ["server"])
            .couldNotAnswer("server", named: "Reading Room")
            .couldNotAnswer("server", named: "Reading Room")
        #expect(listing.silent.map(\.name) == ["Reading Room"])
        #expect(!listing.isWaiting)
    }

    @Test("A library that fails leaves the rows already on screen alone")
    func failureKeepsResults() {
        let listing = SearchListing(term: "bone", local: [held("Bone")], asking: ["server"])
            .couldNotAnswer("server", named: "Reading Room")
        #expect(listing.rows.map(\.result.title) == ["Bone"])
    }

    @Test("Asking a silent library again puts it back in the queue")
    func retryRejoinsTheQueue() {
        let listing = SearchListing(term: "bone", asking: ["server"])
            .couldNotAnswer("server", named: "Reading Room")
            .askingAgain("server")
        #expect(listing.silent.isEmpty)
        #expect(listing.waiting == ["server"])
    }

    @Test("A library that answers after failing loses its notice")
    func answeringClearsTheNotice() {
        let listing = SearchListing(term: "bone", asking: ["server"])
            .couldNotAnswer("server", named: "Reading Room")
            .answered("server", with: [away("Bone")])
        #expect(listing.silent.isEmpty)
        #expect(listing.rows.count == 1)
    }

    @Test("Two libraries are waited for one at a time")
    func waitingShrinks() {
        let start = SearchListing(term: "bone", local: [held("Bone")], asking: ["a", "b"])
        let half = start.answered("a", with: [])
        #expect(half.waiting == ["b"])
        #expect(half.isWaiting)
        #expect(!half.answered("b", with: []).isWaiting)
    }

    @Test("A row is labelled only when more than one place could have answered")
    func labelsOnlyWhenThereIsSomethingToTell() {
        // One folder and nothing asked: every row would say the same words.
        #expect(!SearchListing(term: "bone", local: [held("Bone")]).namesOrigin)
        // The commonest mixed search there is, and the one the shelf's own rule used to
        // hide: a single configured server plus a file another app handed over.
        #expect(SearchListing(
            term: "bone",
            local: [held("Bone", in: .thisDevice)],
            asking: ["server"]
        ).namesOrigin)
        // A folder and a catalogue — the scenario's own situation.
        #expect(SearchListing(term: "bone", local: [held("Bone")], asking: ["server"])
            .namesOrigin)
        // One library, whether it answered locally or remotely, is still one place: a
        // download carries the identity of the library it came from.
        #expect(!SearchListing(
            term: "bone",
            local: [held("Bone", in: Self.server)],
            asking: ["server"]
        ).namesOrigin)
        // Nothing held and one catalogue asked: every row will come from that catalogue.
        #expect(!SearchListing(term: "bone", asking: ["server"]).namesOrigin)
    }

    @Test("The label cannot appear or vanish part-way through a search")
    func labelIsFixedForTheWholeSearch() {
        let start = SearchListing(term: "bone", local: [held("Bone")], asking: ["server"])
        #expect(start.namesOrigin)
        #expect(start.answered("server", with: [away("Carbone")]).namesOrigin)
        #expect(start.couldNotAnswer("server", named: "Reading Room").namesOrigin)
        #expect(start.askingAgain("server").namesOrigin)
    }

    @Test("A late answer never moves a row past another, and can push a heading down")
    func lateAnswersDisplaceHeadingsAndNothingElse() {
        // The exact case the type's doc comment is careful about. Ranked, the device's own
        // answer puts the exact title first and the series under its own heading below it;
        // the server then answers with another title, which lands inside the *first* heading.
        let before = SearchListing(
            term: "bone",
            local: [held("Bone"), held("Bone Chart", kind: .series)],
            asking: ["server"]
        )
        #expect(rendered(before) == ["Bone", "Bone Chart"])

        let after = before.answered("server", with: [away("Carbone")])
        // The flat list is append-only: the new row is last, and nothing before it moved.
        #expect(after.rows.map(\.result.title) == ["Bone", "Bone Chart", "Carbone"])
        // On screen it lands under Titles, so the Series heading and its row shift down one.
        #expect(rendered(after) == ["Bone", "Carbone", "Bone Chart"])
        // What is promised, and pinned here so a change has to argue with it: relative order
        // is preserved, and a row only ever moves *down*.
        let was = try? #require(rendered(before).firstIndex(of: "Bone Chart"))
        let now = try? #require(rendered(after).firstIndex(of: "Bone Chart"))
        #expect(was == 1)
        #expect(now == 2)
    }

    @Test("Nothing typed is nothing found")
    func emptyTerm() {
        #expect(SearchListing(term: "").groups.isEmpty)
    }

    private func publication(_ title: String, from sourceID: UUID?) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            origin: .inferred,
            sourceID: sourceID
        )
    }

    @Test("A publication whose library is gone reads as being on the device")
    func removedLibraryReadsAsDevice() {
        let row = FoundRow.held(
            publication("Bone", from: UUID()),
            kind: .publication,
            in: SourceRegistry(sources: [])
        )
        #expect(row.origin == .thisDevice)
    }

    @Test("A publication carries the name its library was given")
    func heldRowsAreLabelled() {
        let source = Source(displayName: "Attic NAS", kind: .localFolder)
        let rows = FoundRow.held(
            in: [
                MatchGroup(kind: .publication, publications: [publication("Bone", from: source.id)])
            ],
            registry: SourceRegistry(sources: [source])
        )
        #expect(rows.map(\.origin) == [.library(id: source.id.uuidString, name: "Attic NAS")])
    }
}
