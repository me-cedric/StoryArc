import Foundation
import Kavita
import StoryArcCore
import Testing

@testable import LibraryFeature

/// What one chapter of a server's library looks like as a row.
///
/// `library-browsing` asks for "publications from every configured source" with "nothing on
/// the shelf [stating] which source a publication came from", so a server's row has to be
/// the same kind of thing a scanned file is and differ only in having nothing on disk.
///
/// Android's `KavitaContributorTest` makes the same claims.
struct KavitaContributorTests {

    private let source = UUID()

    private func row(
        series: KavitaSeries = KavitaSeries(id: 312, name: "Lantern Green", libraryId: 2, format: 1),
        chapter: KavitaChapter = KavitaChapter(id: 3103, number: "43", title: "Issue #43", pages: 22)
    ) -> Publication {
        KavitaContributor.publication(source: source, series: series, chapter: chapter)
    }

    @Test("A chapter is identified by the server, not by a path")
    func identity() {
        let publication = row()

        #expect(publication.identity.serverIdentifier?.sourceID == source)
        #expect(publication.identity.serverIdentifier?.remoteID == "chapter:3103")
        #expect(publication.identity.normalizedPath == nil)
    }

    @Test("It carries what a row is drawn from")
    func fields() {
        let publication = row()

        #expect(publication.displayTitle == "Issue #43")
        #expect(publication.series == "Lantern Green")
        #expect(publication.number == "43")
        #expect(publication.pageCount == 22)
        #expect(publication.sourceID == source)
    }

    @Test("A chapter Kavita gave no number is called by its series")
    func sentinelNumber() {
        // Kavita writes -100000 for a chapter with no number — a collected edition, a
        // volume with one part. The library drew shelves of cells titled "-100000".
        let publication = row(chapter: KavitaChapter(id: 1, number: "-100000", title: ""))

        #expect(publication.displayTitle == "Lantern Green")
        // And the sentinel is not kept as the number either. It was, and `#<number>` is
        // drawn on its own under the title — so the row read "Lantern Green" over a line
        // reading "Lantern Green #-100000", which is what a reader reported.
        #expect(publication.number == nil)
    }

    @Test("A numbered chapter is named for its series and its number, not the number alone")
    func numbered() {
        // A shelf of cells headed "43" names nothing. `<series> #<number>` is the house
        // format, so a server's issue and a scanned one read the same.
        let publication = row(chapter: KavitaChapter(id: 1, number: "7", title: ""))

        #expect(publication.displayTitle == "Lantern Green #7")
        #expect(publication.number == "7")
    }

    @Test("The server owns the metadata, so a downloaded file does not overwrite it")
    func origin() {
        #expect(row().origin == .authoritative)
    }

    @Test("Each of Kavita's formats files under one this app can filter")
    func formats() {
        func format(_ kavita: Int) -> PublicationFormat {
            row(series: KavitaSeries(id: 1, name: "Lantern", libraryId: 2, format: kavita)).format
        }

        #expect(format(0) == .imageFolder)
        #expect(format(3) == .epub)
        #expect(format(4) == .pdf)
        // Kavita says "archive" and not which archive, so a CBR on a server is listed as a
        // CBZ until it is downloaded. Pinned so the guess is visible rather than folklore.
        #expect(format(1) == .cbz)
        #expect(format(2) == .cbz)
    }
}
