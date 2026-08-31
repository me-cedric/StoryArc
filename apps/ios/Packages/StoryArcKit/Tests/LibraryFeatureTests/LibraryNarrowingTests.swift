import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which libraries the filter offers to narrow to, and when it offers any at all.
///
/// The rule rather than the pixels: a menu can be read off a screenshot, but the decisions
/// under it — that the group is absent below two libraries, that "Any library" is always
/// first, that the registry's order is the reader's — are the parts that go wrong quietly.
///
/// This suite was written for `ScopeMenu.offered(in:)`, when narrowing to one library was a
/// *scope* with a control of its own in the toolbar. The `one-library-three-destinations`
/// amendment removed that shape — "it is offered by name as a filter … and not as a scope the
/// view is in" — so the same rule now answers for ``FilterMenu``'s first group, and the tests
/// moved with it rather than being deleted and rewritten.
///
/// Android's `LibraryIndexTest` asserts the same gate through `attributesPublications`.
@Suite("Libraries the filter offers")
struct OfferedLibrariesTests {

    private func source(_ name: String) -> Source {
        Source(displayName: name, kind: .opdsCatalog)
    }

    @Test("A registry with no sources offers no library group at all")
    func emptyRegistryOffersNothing() {
        // Not "Any library" on its own. A reader with nothing added has nothing to narrow to,
        // and a group with one row is a control that cannot be used.
        #expect(LibraryNarrowing.offeredLibraries(in: SourceRegistry()).isEmpty)
    }

    @Test("One source offers nothing, because there is nothing to choose between")
    func oneSourceOffersNothing() {
        let registry = SourceRegistry(sources: [source("Standard Ebooks")])
        #expect(LibraryNarrowing.offeredLibraries(in: registry).isEmpty)
    }

    @Test("Two sources offer every source and the whole library, in registry order")
    func twoSourcesOfferEverything() {
        let first = source("Standard Ebooks")
        let second = source("Attic NAS")
        let registry = SourceRegistry(sources: [first, second])

        #expect(
            LibraryNarrowing.offeredLibraries(in: registry) == [
                .allSources,
                .source(first.id),
                .source(second.id),
            ]
        )
    }

    @Test("A folder counts towards the gate, because its publications are on the shelf")
    func foldersCountTowardsTheGate() {
        // A folder is not a place to browse *to* — the sidebar leaves it out — but its
        // comics are in the grid, so narrowing to it is a question with an answer.
        let folder = Source(displayName: "Comics", kind: .localFolder)
        let server = source("Attic NAS")
        let registry = SourceRegistry(sources: [folder, server])

        #expect(LibraryNarrowing.offeredLibraries(in: registry).count == 3)
        #expect(LibraryNarrowing.offeredLibraries(in: registry).contains(.source(folder.id)))
    }

    @Test("Every offered library survives being resolved against the registry it came from")
    func offeredScopesAreLive() {
        // A group that offered a narrowing the library would immediately resolve back to
        // "all sources" would be a row that silently does nothing when tapped.
        let registry = SourceRegistry(sources: [source("A"), source("B"), source("C")])
        for scope in LibraryNarrowing.offeredLibraries(in: registry) {
            #expect(scope.resolved(in: registry) == scope)
        }
    }

    @Test("The gate is the one Android uses, not a second opinion")
    func gateMatchesAndroid() {
        // `attributesPublications` is what decides whether a publication shows its source,
        // and it is what Android's own filter section gates on. Two rules that mean "more
        // than one source" is how the two apps drift apart.
        let one = SourceRegistry(sources: [source("A")])
        let two = SourceRegistry(sources: [source("A"), source("B")])

        #expect(LibraryNarrowing.offeredLibraries(in: one).isEmpty == !one.attributesPublications)
        #expect(LibraryNarrowing.offeredLibraries(in: two).isEmpty == !two.attributesPublications)
    }
}

/// What is narrowing the shelf, what the filter control says about it, and what one action
/// undoes.
///
/// **This is the defect's own suite.** `ScopeMenu` wrote `query.scope` from a picker in the
/// toolbar; `LibraryQuery.activeFilterCount` did not count it and `withoutFilters` did not
/// clear it. A reader could be looking at one library's shelf with nothing on screen offering
/// to undo it — which `library-browsing` forbids in as many words: "clearing filters restores
/// the whole library, so **there is no state a reader can be left in without noticing**".
///
/// Every assertion here is the shape Android already had: `narrowingCount` counts the query's
/// facets plus the library plus the download group, and the two `onClear` closures in
/// `LibraryScreen` put all of them and the availability axis back.
@Suite("What narrowing counts and what clearing clears")
struct NarrowingRuleTests {

    private let library = LibraryScope.source(UUID())

    private func narrowing(
        _ query: LibraryQuery,
        downloads: DownloadFilter = .either,
        availability: LibraryAvailability = .everywhere
    ) -> LibraryNarrowing {
        LibraryNarrowing(query: query, downloads: downloads, availability: availability)
    }

    @Test("A library nobody has narrowed counts nothing and offers nothing to clear")
    func untouchedLibraryIsNotNarrowed() {
        #expect(narrowing(LibraryQuery()).activeCount == 0)
        #expect(!narrowing(LibraryQuery()).isActive)
    }

    @Test("Narrowing to one library is counted, like every other filter")
    func theLibraryNarrowingIsCounted() {
        // The half of the defect a reader *could* have seen: the funnel drew itself
        // untouched over a shelf it had cut to one library.
        #expect(narrowing(LibraryQuery(scope: library)).activeCount == 1)
        #expect(narrowing(LibraryQuery(scope: library)).isActive)
    }

    @Test("The three narrowings add up rather than counting the query's alone")
    func everyGroupIsCounted() {
        let query = LibraryQuery(readStates: [.unread], genres: ["Manga"], scope: library)

        // Two facets, one library, one download group.
        #expect(narrowing(query, downloads: .downloaded).activeCount == 4)
    }

    @Test("Clearing puts the library back, which is the whole defect")
    func clearingWidensTheLibrary() {
        let cleared = narrowing(LibraryQuery(scope: library)).cleared()

        #expect(cleared.query.scope == .allSources)
        #expect(!cleared.isScoped)
        #expect(cleared.activeCount == 0)
    }

    @Test("Clearing puts every narrowing back at once, the axis included")
    func clearingUndoesEverythingItCounts() {
        let query = LibraryQuery(
            readStates: [.unread],
            formats: [.cbz],
            genres: ["Manga"],
            years: YearRange(from: 1986, to: 1995),
            scope: library
        )
        let cleared = narrowing(query, downloads: .downloaded, availability: .onThisDevice)
            .cleared()

        #expect(cleared.activeCount == 0)
        #expect(cleared.downloads == .either)
        // Not counted, and still cleared — a cleared shelf still showing only what is on
        // this device is as empty as the reader found it.
        #expect(cleared.availability == .everywhere)
    }

    @Test("Clearing leaves the sort and the direction where the reader put them")
    func clearingKeepsTheOrder() {
        // `library-browsing` asks for the filters to be cleared, not the arrangement. A
        // reader who sorted by last read and then cleared a filter did not ask to go back
        // to A–Z.
        let query = LibraryQuery(sort: .lastRead, ascending: false, scope: library)
        let cleared = narrowing(query).cleared()

        #expect(cleared.query.sort == .lastRead)
        #expect(cleared.query.ascending == false)
    }

    @Test("The filter menu keeps the search; the empty state clears it")
    func onlyTheEmptyStateClearsTheSearch() {
        // Two callers, one rule, one deliberate difference. The menu clears filters while
        // the reader is still looking at results for a word they typed; the empty state is
        // offering to undo everything that could be hiding a match.
        let query = LibraryQuery(search: "orbit", scope: library)

        #expect(narrowing(query).cleared().query.search == "orbit")
        #expect(narrowing(query).cleared(includingSearch: true).query.search.isEmpty)
    }

    @Test("The availability axis alone is not a filter, and is not counted as one")
    func availabilityIsNotCounted() {
        // It is the separate primary axis: its own control states it while it is set, and
        // the empty state offers to widen it by name. A badge reading "1 filter active" for
        // a choice the reader can see on the toolbar would be counting the visible thing
        // and — as shipped — not the invisible one.
        #expect(narrowing(LibraryQuery(), availability: .onThisDevice).activeCount == 0)
    }

    @Test("Clearing is idempotent, so a second tap changes nothing")
    func clearingTwiceIsClearingOnce() {
        let query = LibraryQuery(tags: ["Noir"], scope: library)
        let once = narrowing(query, downloads: .notDownloaded, availability: .onThisDevice)
            .cleared()

        #expect(once.cleared() == once)
    }
}
