import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// That a publication offered by a source and the same publication downloaded are one row.
///
/// `library-browsing` asks for one row, and the library drew two: a server row carries a
/// `ServerIdentifier` and no path, a downloaded file carries a path and a digest and no
/// server identifier, and `PublicationIdentity.matches` had nothing in common to match on.
/// A reader who downloaded a Kavita chapter watched a second copy of it appear.
///
/// Android's `DownloadFoldTest` asserts the same claims, case for case.
@Suite("A download joins the row it came from")
struct DownloadFoldTests {

    private let source = UUID()

    /// What a Kavita source puts on the shelf: an identifier, and nothing on disk.
    private var remote: Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "chapter:3103")
            ),
            format: .cbz,
            displayTitle: "Lantern Green #43",
            series: "Lantern Green",
            origin: .authoritative,
            sourceID: source
        )
    }

    /// What the scanner makes of the bytes once they are on disk.
    private var downloaded: Publication {
        Publication(
            identity: PublicationIdentity(
                contentDigest: "8f14e45fceea167a5a36dedd4bea2543",
                normalizedPath: "/var/mobile/Containers/Data/Application/downloads/lantern-green-43.cbz"
            ),
            format: .cbz,
            displayTitle: "lantern-green-43",
            origin: .inferred
        )
    }

    private func card(sourceId: String? = nil) -> KavitaCard {
        KavitaCard(
            publicationId: downloaded.id,
            downloadId: "kavita:\(source):3103",
            sourceId: sourceId ?? source.uuidString,
            seriesId: 312,
            chapterId: 3103,
            seriesName: "Lantern Green",
            chapterName: "Lantern Green #43"
        )
    }

    @Test("A downloaded chapter and the row it came from are one row")
    func oneRow() {
        let linked = DownloadFold.described(downloaded, card: card())

        #expect(
            linked.identity.matches(remote.identity),
            "The downloaded copy does not match the row the source put on the shelf."
        )
        #expect(DownloadFold.rowFor([remote], downloaded: linked) == 0)
    }

    @Test("Without the fold they are two rows, which is the defect")
    func theControl() {
        #expect(!downloaded.identity.matches(remote.identity))
        #expect(DownloadFold.rowFor([remote], downloaded: downloaded) == nil)
    }

    @Test("The row keeps its key when the path arrives")
    func theKeyIsStable() {
        // `stableID` prefers a path, so a row that took the downloaded copy's identity
        // would change key from `srv:…` to `path:…` — and reading progress, shelves and
        // bookmarks are all filed under that key.
        let rows = [remote]
        let at = DownloadFold.rowFor(rows, downloaded: DownloadFold.described(downloaded, card: card()))

        #expect(at == 0)
        #expect(remote.id == "srv:\(source):chapter:3103")
        #expect(rows[at ?? 0].id == "srv:\(source):chapter:3103")
    }

    @Test("The card's identifier is spelled the way the contributor spells it")
    func theSpellingMatches() {
        // The two are written in different files and neither compiles against the other.
        // A chapter prefix changed in one place and not the other is a fold that silently
        // stops folding, and a duplicate row is what a reader would see.
        #expect(card().remoteIdentity == remote.identity.serverIdentifier)
    }

    @Test("A download with no card is left alone, because it has no row to join")
    func noCard() {
        let linked = DownloadFold.described(downloaded, card: nil)

        #expect(linked.identity == downloaded.identity)
        #expect(DownloadFold.rowFor([remote], downloaded: linked) == nil)
    }

    @Test("A card whose source is not this app's is ignored rather than crashing")
    func aForeignCard() {
        let foreign = card(sourceId: "not-a-uuid")

        #expect(foreign.remoteIdentity == nil)
        #expect(DownloadFold.described(downloaded, card: foreign).identity == downloaded.identity)
    }

    @Test("The file is still what the row opens, so it reads with no network")
    func theFileIsKept() {
        let linked = DownloadFold.described(downloaded, card: card())

        #expect(
            linked.identity.normalizedPath
                == "/var/mobile/Containers/Data/Application/downloads/lantern-green-43.cbz"
        )
    }

    /// What an OPDS catalogue puts on the shelf: a server identifier built the way
    /// `OpdsContributor` spells it, and no card — Kavita's own bridge.
    private var opdsRemote: Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "opds:urn:uuid:bone")
            ),
            format: .cbz,
            displayTitle: "Bone",
            origin: .authoritative,
            sourceID: source
        )
    }

    /// What `DownloadQueue/downloadID(for:sourceID:)` keys an OPDS download's record under.
    private var opdsDownload: Download {
        Download(
            id: "opds:\(source.uuidString):urn:uuid:bone",
            sourceID: source,
            title: "Bone",
            remote: URL(string: "https://catalogue.test/entries/bone")!,
            mediaType: "application/vnd.comicbook+zip",
            state: .finished
        )
    }

    @Test("An OPDS download joins its catalogue row too, with no card at all")
    func opdsRowOneToo() {
        let linked = DownloadFold.described(downloaded, card: nil, record: opdsDownload)

        #expect(
            linked.identity.matches(opdsRemote.identity),
            "The downloaded copy does not match the catalogue row it came from."
        )
        #expect(DownloadFold.rowFor([opdsRemote], downloaded: linked) == 0)
        // The cached catalogue description is kept — dl-core 1.4 asks for exactly that —
        // because no card means nothing overwrites `downloaded`'s own title.
        #expect(linked.displayTitle == downloaded.displayTitle)
    }

    @Test("A download whose id is not the queue's own OPDS shape is left alone")
    func notAnOpdsId() {
        let kavita = Download(
            id: "kavita:\(source):3103",
            sourceID: source,
            title: "Lantern Green #43",
            remote: URL(string: "https://kavita.test/api/download/chapter?chapterId=3103")!,
            mediaType: "application/vnd.comicbook+zip",
            state: .finished
        )
        #expect(DownloadFold.opdsIdentity(for: kavita) == nil)
        #expect(DownloadFold.described(downloaded, card: nil, record: kavita).identity == downloaded.identity)
    }

    @Test("A download with no source is left alone, because the id carries no source to key on")
    func noSource() {
        let unscoped = Download(
            id: "urn:uuid:bone",
            title: "Bone",
            remote: URL(string: "https://catalogue.test/entries/bone")!,
            mediaType: "application/vnd.comicbook+zip",
            state: .finished
        )
        #expect(DownloadFold.opdsIdentity(for: unscoped) == nil)
    }
}
