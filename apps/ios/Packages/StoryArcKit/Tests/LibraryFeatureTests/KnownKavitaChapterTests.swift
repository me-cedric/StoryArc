import Foundation
import Kavita
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which publication a browsed Kavita chapter's full menu acts on.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn* names "a server's
/// own browser" among the places — `KavitaChapterList` offers *Start from the beginning*
/// and *Show details* only for a chapter this device has already indexed, for the same
/// reason `KnownCatalogueEntryTests` gives for an OPDS row. `knownKavitaChapter(sourceId:
/// series:chapter:in:)` is the rule it asks, lifted out so a test can reach it without
/// rendering the row.
struct KnownKavitaChapterTests {
    private let source = UUID()
    private let series = KavitaSeries(id: 312, name: "Lantern Green", libraryId: 2, format: 1)

    private func chapter(id: Int = 3103) -> KavitaChapter {
        KavitaChapter(id: id, number: "43", title: "Issue #43", pages: 22)
    }

    @Test("A chapter the library has already indexed resolves to its own publication, by id")
    func indexedChapterResolves() {
        let indexed = KavitaContributor.publication(source: source, series: series, chapter: chapter())
        let other = KavitaContributor.publication(source: source, series: series, chapter: chapter(id: 9))

        // The other chapter's publication is listed first, so a function that merely took
        // the first publication in the library — rather than matching by id — would pass
        // this with the wrong row.
        let found = knownKavitaChapter(
            sourceId: source.uuidString, series: series, chapter: chapter(), in: [other, indexed]
        )
        #expect(found?.id == indexed.id)
    }

    @Test("A chapter browsed past the indexed series resolves to nothing")
    func unindexedChapterResolvesToNothing() {
        let other = KavitaContributor.publication(source: source, series: series, chapter: chapter(id: 9))
        #expect(knownKavitaChapter(sourceId: source.uuidString, series: series, chapter: chapter(), in: [other]) == nil)
    }

    @Test("An unparseable source id resolves to nothing, whatever the library holds")
    func unparseableSourceResolvesToNothing() {
        let indexed = KavitaContributor.publication(source: source, series: series, chapter: chapter())
        #expect(knownKavitaChapter(sourceId: "not-a-uuid", series: series, chapter: chapter(), in: [indexed]) == nil)
    }
}
