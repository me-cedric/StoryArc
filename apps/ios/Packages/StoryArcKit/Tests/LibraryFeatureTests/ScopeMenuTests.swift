import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the library's scope selector offers, and when it is there at all.
///
/// The rule rather than the pixels, for the reason `LibrarySidebarTests` asserts
/// `SidebarDestination.all(for:)`: a menu can be read off a screenshot, but the decisions
/// under it — that the control is absent below two sources, that "All sources" is always
/// first, that the registry's order is the reader's — are the parts that go wrong quietly.
///
/// This suite exists because the control was written, translated into four languages and
/// mounted by nothing: `ScopeMenu` had no caller, so an iOS reader could not leave "all
/// sources", and the no-results state's offer to widen back to every source could never
/// draw because nothing could narrow away from it. `LibraryToolbar` now asks
/// ``ScopeMenu/offered(in:)`` whether to mount the control, so the gate below is the same
/// value the toolbar reads.
///
/// Android's `LibraryIndexTest` asserts the same gate through `attributesPublications`.
@Suite("Library scope menu")
struct ScopeMenuTests {

    private func source(_ name: String) -> Source {
        Source(displayName: name, kind: .opdsCatalog)
    }

    @Test("A registry with no sources offers no scope at all")
    func emptyRegistryOffersNothing() {
        // Not "All sources" on its own. A reader with nothing added has nothing to scope,
        // and a selector with one row is a control that cannot be used.
        #expect(ScopeMenu.offered(in: SourceRegistry()).isEmpty)
    }

    @Test("One source offers no scope, because there is nothing to choose between")
    func oneSourceOffersNothing() {
        let registry = SourceRegistry(sources: [source("Standard Ebooks")])
        #expect(ScopeMenu.offered(in: registry).isEmpty)
    }

    @Test("Two sources offer every source and the whole library, in registry order")
    func twoSourcesOfferEverything() {
        let first = source("Standard Ebooks")
        let second = source("Attic NAS")
        let registry = SourceRegistry(sources: [first, second])

        #expect(
            ScopeMenu.offered(in: registry) == [
                .allSources,
                .source(first.id),
                .source(second.id),
            ]
        )
    }

    @Test("A folder counts towards the gate, because its publications are on the shelf")
    func foldersCountTowardsTheGate() {
        // A folder is not a place to browse *to* — the sidebar leaves it out — but its
        // comics are in the grid, so scoping to it is a question with an answer.
        let folder = Source(displayName: "Comics", kind: .localFolder)
        let server = source("Attic NAS")
        let registry = SourceRegistry(sources: [folder, server])

        #expect(ScopeMenu.offered(in: registry).count == 3)
        #expect(ScopeMenu.offered(in: registry).contains(.source(folder.id)))
    }

    @Test("Every offered scope survives being resolved against the registry it came from")
    func offeredScopesAreLive() {
        // A menu that offered a scope the library would immediately resolve back to "all
        // sources" would be a row that silently does nothing when tapped.
        let registry = SourceRegistry(sources: [source("A"), source("B"), source("C")])
        for scope in ScopeMenu.offered(in: registry) {
            #expect(scope.resolved(in: registry) == scope)
        }
    }

    @Test("The gate is the one Android uses, not a second opinion")
    func gateMatchesAndroid() {
        // `attributesPublications` is what decides whether a publication shows its source,
        // and it is what Android's `LibraryScreen` gates its own selector on. Two rules
        // that mean "more than one source" is how the two apps drift apart.
        let one = SourceRegistry(sources: [source("A")])
        let two = SourceRegistry(sources: [source("A"), source("B")])

        #expect(ScopeMenu.offered(in: one).isEmpty == !one.attributesPublications)
        #expect(ScopeMenu.offered(in: two).isEmpty == !two.attributesPublications)
    }
}

/// That a narrowed library can be widened again, which is the offer the missing control
/// made unreachable.
@Suite("Widening a narrowed library")
@MainActor
struct WidenScopeTests {

    @Test("Widening returns the library to every source")
    func widenReturnsToAllSources() {
        let model = LibraryModel()
        model.query.scope = .source(UUID())

        model.widenToAllSources()

        #expect(model.query.scope == .allSources)
    }

    @Test("Widening leaves the search and the filters where the reader put them")
    func widenKeepsTheRestOfTheQuery() {
        // `library-browsing` asks the no-results state for two separate offers: widen the
        // scope, or clear the filters. A widen that also cleared the filters would collapse
        // them into one, and the reader who wanted the same words put to the rest of their
        // library would get their filters undone as well.
        let model = LibraryModel()
        model.query.scope = .source(UUID())
        model.query.search = "orbit"
        model.query.genres = ["Manga"]

        model.widenToAllSources()

        #expect(model.query.scope == .allSources)
        #expect(model.query.search == "orbit")
        #expect(model.query.genres == ["Manga"])
    }
}
