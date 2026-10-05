import Catalogue
import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which publication a catalogue entry's full menu acts on.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn* names "a server's
/// own browser" among the places — `CatalogueEntryLink` offers the full menu only for an
/// entry this device has already indexed, because `LibraryModel.keepOffline(_:)` and
/// `AddToShelfMenu` both resolve a publication by finding its id inside `model.publications`.
/// `knownCatalogueEntry(source:entry:in:)` is the rule it asks, lifted out so a test can
/// reach it without rendering the cell.
struct KnownCatalogueEntryTests {
    private let source = UUID()

    private func entry(id: String = "urn:uuid:1") -> OpdsEntry {
        OpdsEntry(
            id: id,
            title: "Tidal Reach",
            acquisitions: [
                OpdsAcquisition(
                    href: URL(string: "https://example/get")!,
                    mediaType: "application/vnd.comicbook+zip",
                    kind: .open
                ),
            ]
        )
    }

    @Test("An entry the library has already indexed resolves to its own publication, by id")
    func indexedEntryResolves() throws {
        let indexed = try #require(OpdsContributor.publication(source: source, entry: entry()))
        let other = try #require(OpdsContributor.publication(source: source, entry: entry(id: "urn:uuid:9")))

        // The other entry's publication is listed first, so a function that merely took the
        // first publication in the library — rather than matching by id — would pass this
        // with the wrong row.
        let found = knownCatalogueEntry(source: source, entry: entry(), in: [other, indexed])
        #expect(found?.id == indexed.id)
    }

    @Test("An entry browsed past the indexed slice resolves to nothing")
    func unindexedEntryResolvesToNothing() throws {
        let other = try #require(OpdsContributor.publication(source: source, entry: entry(id: "urn:uuid:9")))
        #expect(knownCatalogueEntry(source: source, entry: entry(), in: [other]) == nil)
    }

    @Test("A navigation entry with nothing to act on resolves to nothing")
    func navigationEntryResolvesToNothing() {
        let navigation = OpdsEntry(id: "urn:uuid:2", title: "A folder", acquisitions: [])
        #expect(knownCatalogueEntry(source: source, entry: navigation, in: []) == nil)
    }
}
