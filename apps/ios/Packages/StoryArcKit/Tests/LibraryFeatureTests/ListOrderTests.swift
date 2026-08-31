import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What a reader may do to a curated order, and what they may not.
///
/// `library-browsing`'s *Default order in a reading list* and *Overriding a curated order*,
/// which are three promises: the curated order is the default, another field applies for the
/// session, and "the curated order itself is not modified". The third is the one that would
/// rot quietly — a sort that wrote back, or a drag taken while a sort was overriding the
/// list, scrambles someone else's reading path and nothing on screen says so until the next
/// time it is opened.
///
/// Android's `ListOrderTest` asserts these cases one for one.
@Suite("Reading list order")
struct ListOrderTests {

    // MARK: - Fixtures

    /// Three publications whose title order is deliberately not their list order.
    private let library: [Publication] = [
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/nightjar.cbz"),
            format: .cbz,
            displayTitle: "Nightjar",
            year: 1994,
            origin: .inferred
        ),
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/ashfall.cbz"),
            format: .cbz,
            displayTitle: "Ashfall",
            year: 2011,
            origin: .inferred
        ),
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/cinders.cbz"),
            format: .cbz,
            displayTitle: "Cinders",
            year: 2003,
            origin: .inferred
        )
    ]

    /// The curated order: what someone laid out, which is none of the sorts below.
    private var curatedEntries: [String] {
        ["path:/fixtures/nightjar.cbz", "path:/fixtures/ashfall.cbz", "path:/fixtures/cinders.cbz"]
    }

    private func titles(_ ids: [String]) -> [String] {
        ids.map { id in library.first { $0.id == id }?.displayTitle ?? id }
    }

    private func byTitle(_ ascending: Bool = true) -> ListOrder {
        ListOrder(sort: .title, ascending: ascending)
    }

    // MARK: - The default

    @Test("A list opens in the order it was made in, not alphabetically")
    func curatedIsTheDefault() {
        #expect(ListOrder.curated.isCurated)
        #expect(ListOrder.curated.sort == nil)
        let shown = ListOrdering.arrange(curatedEntries, by: .curated, publications: library)
        #expect(titles(shown) == ["Nightjar", "Ashfall", "Cinders"])
    }

    @Test("The curated order is handed back rather than re-sorted into itself")
    func curatedIsNotRunThroughAComparator() {
        // Identity, not "sorted by whatever the curated order happens to look like". An
        // entry the library cannot answer for proves it: nothing could sort that one, and it
        // still comes back exactly where the list put it.
        let entries = ["b", "gone", "a"]
        #expect(ListOrdering.arrange(entries, by: .curated, publications: library) == entries)
    }

    // MARK: - Overriding it

    @Test("A chosen field reorders what is drawn")
    func aChosenFieldApplies() {
        let shown = ListOrdering.arrange(curatedEntries, by: byTitle(), publications: library)
        #expect(titles(shown) == ["Ashfall", "Cinders", "Nightjar"])
    }

    @Test("Descending is the same order the other way round")
    func directionReverses() {
        let shown = ListOrdering.arrange(curatedEntries, by: byTitle(false), publications: library)
        #expect(titles(shown) == ["Nightjar", "Cinders", "Ashfall"])
    }

    @Test("A chosen field uses the library's own comparator rather than a second one")
    func theComparatorIsTheLibrarys() {
        // The reason this matters is collation: a list sorted by title has to agree with the
        // shelf about where an accented title goes, and two comparators would eventually
        // disagree without either of them looking wrong.
        let shown = ListOrdering.arrange(curatedEntries, by: ListOrder(sort: .year), publications: library)
        let shelf = LibraryIndex.arrange(library, query: LibraryQuery(sort: .year)).map(\.id)
        #expect(shown == shelf)
    }

    @Test("A chosen field reaches the progress the sort asks about")
    func progressReachesTheComparator() {
        // Last read is one of the seven fields, and it is answerable only from outside the
        // publication. A closure that never arrived would sort every entry as never-read and
        // leave the list in its curated order while claiming to have sorted it.
        let read: [String: Date] = [
            "path:/fixtures/cinders.cbz": Date(timeIntervalSince1970: 3_000),
            "path:/fixtures/nightjar.cbz": Date(timeIntervalSince1970: 1_000)
        ]
        let shown = ListOrdering.arrange(
            curatedEntries,
            by: ListOrder(sort: .lastRead),
            publications: library
        ) { publication in
            LibraryIndex.Progress(state: .inProgress, fraction: 0.5, lastReadAt: read[publication.id])
        }
        // Most recent first, and the one never opened last — the shelf's own rule.
        #expect(titles(shown) == ["Cinders", "Nightjar", "Ashfall"])
    }

    // MARK: - What is not touched

    @Test("Sorting does not modify the curated order")
    func theCuratedOrderSurvives() {
        let entries = curatedEntries
        _ = ListOrdering.arrange(entries, by: byTitle(), publications: library)
        #expect(entries == curatedEntries)
        // And returning to it gives back exactly what the list holds.
        #expect(ListOrdering.arrange(entries, by: .curated, publications: library) == curatedEntries)
    }

    @Test("Entries may be rearranged in the curated order and nowhere else")
    func reorderingIsRefusedUnderASort() {
        // A drag or an arrow reports the position it landed in *as drawn*. Taken while a
        // sort was overriding the list, that position would be written into the curated
        // order — which is precisely what the third clause forbids.
        #expect(ListOrder.curated.allowsReordering)
        #expect(!byTitle().allowsReordering)
        #expect(!ListOrder(sort: .progress, ascending: false).allowsReordering)
    }

    // MARK: - Entries nothing can answer for

    @Test("An entry the library cannot answer for keeps the tail, in the list's own order")
    func unavailableEntriesKeepTheTail() {
        // It is not dropped — the list still holds it — and it is not sorted on facts nobody
        // has. Last, and in the list's own order among its own kind, is what is decidable.
        let entries = ["gone-b", "path:/fixtures/nightjar.cbz", "gone-a", "path:/fixtures/ashfall.cbz"]
        let shown = ListOrdering.arrange(entries, by: byTitle(), publications: library)
        #expect(shown == ["path:/fixtures/ashfall.cbz", "path:/fixtures/nightjar.cbz", "gone-b", "gone-a"])
    }

    @Test("Nothing is lost or invented by sorting")
    func everyEntrySurvives() {
        let entries = curatedEntries + ["gone"]
        let shown = ListOrdering.arrange(entries, by: byTitle(), publications: library)
        #expect(Set(shown) == Set(entries))
        #expect(shown.count == entries.count)
    }

    // MARK: - Numbering

    @Test("The number beside a row is its place in the list, never its place on screen")
    func positionsAreTheListsOwn() {
        let numbers = ListOrdering.positions(in: curatedEntries)
        #expect(numbers["path:/fixtures/nightjar.cbz"] == 1)
        #expect(numbers["path:/fixtures/ashfall.cbz"] == 2)
        #expect(numbers["path:/fixtures/cinders.cbz"] == 3)

        // Sorted by title, Ashfall is drawn first and is still the second entry in the list.
        let shown = ListOrdering.arrange(curatedEntries, by: byTitle(), publications: library)
        #expect(shown.first == "path:/fixtures/ashfall.cbz")
        #expect(numbers[shown[0]] == 2)
    }

    @Test("An empty list numbers nothing")
    func emptyListHasNoPositions() {
        #expect(ListOrdering.positions(in: []).isEmpty)
        #expect(ListOrdering.arrange([], by: byTitle(), publications: library).isEmpty)
    }
}
