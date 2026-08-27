import Foundation
import Testing

@testable import StoryArcCore

/// Which source a publication came from.
///
/// `library-browsing` needs it to order two sources holding one title, and `sources` needs
/// it for a source's item count. Neither was answerable before, which is why a flat list of
/// files was as far as the library could go. Android's `PublicationAttributionTest` asserts
/// the same two things.
@Suite("Publication attribution")
struct PublicationAttributionTests {

    @Test("A publication carries no source until one attributes it")
    func unattributedByDefault() {
        // `nil` means unattributed rather than local. A file the system hands over belongs
        // to no source the reader configured, and claiming otherwise would put it in a
        // source's item count.
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/one.cbz"),
            format: .cbz,
            displayTitle: "One",
            origin: .inferred
        )

        #expect(publication.sourceID == nil)
    }

    @Test("Attributing a publication keeps everything else about it")
    func attributionPreservesTheRest() {
        // The indexer's answer about what a publication *is* must survive the library's
        // answer about where it came from.
        let source = UUID()
        var publication = Publication(
            identity: PublicationIdentity(contentDigest: "digest"),
            format: .epub,
            displayTitle: "Two",
            series: "A series",
            origin: .embedded
        )
        let before = publication

        publication.sourceID = source

        #expect(publication.sourceID == source)
        #expect(publication.displayTitle == before.displayTitle)
        #expect(publication.series == before.series)
        #expect(publication.identity == before.identity)
        #expect(before.sourceID == nil)
    }
}
