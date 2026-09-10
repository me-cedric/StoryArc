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
}
