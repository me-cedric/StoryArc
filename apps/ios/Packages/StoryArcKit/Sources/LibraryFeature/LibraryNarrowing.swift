internal import Foundation

internal import StoryArcCore

/// Everything narrowing the shelf at once, what the filter control says about it, and what
/// one action undoes.
///
/// `library-browsing`, as amended by `one-library-three-destinations`, is explicit on all
/// three counts. Narrowing to one library "is offered by name as a filter … and not as a
/// scope the view is in"; filters "combine with AND, the active count is visible on the
/// filter control, and a single action clears them all"; and "clearing filters restores the
/// whole library, **so there is no state a reader can be left in without noticing**".
///
/// iOS met none of the three for the library narrowing. `ScopeMenu` wrote `query.scope` from
/// a picker in the toolbar — a scope, which is what the amendment removed — and neither the
/// filter menu's count nor its *Clear filters* knew the field existed. A reader could be
/// looking at one library's shelf with nothing on screen offering to undo it.
///
/// The three narrowings are held apart in three places for reasons each of them has:
/// `LibraryQuery` is the value both platforms encode, the download group is a screen field
/// beside it, and availability is an `@AppStorage` axis of its own. Nothing joined them up,
/// so every call site that wanted "all of it" composed its own answer and two of them
/// composed it differently. This is that answer, once, pure, and asserted — Android reaches
/// it with `narrowingCount` and the two `onClear` closures in `LibraryScreen`.
struct LibraryNarrowing: Equatable, Sendable {
    var query: LibraryQuery
    var downloads: DownloadFilter
    var availability: LibraryAvailability

    init(
        query: LibraryQuery,
        downloads: DownloadFilter = .either,
        availability: LibraryAvailability = .everywhere
    ) {
        self.query = query
        self.downloads = downloads
        self.availability = availability
    }

    /// Whether the shelf is narrowed to one library.
    var isScoped: Bool { query.scope != .allSources }

    /// How much of the library the reader has hidden with the filter control.
    ///
    /// `LibraryQuery.activeFilterCount` counts the seven facets it holds and cannot count the
    /// other two, which are fields beside it rather than in it. Counted here so the number
    /// the control speaks matches what *Clear filters* undoes — a control saying "2 filters
    /// active" that clears three things is one nobody trusts twice.
    ///
    /// **Availability is not in it, and is cleared below.** It is not a filter: the amendment
    /// makes it "the separate primary axis", it has a control of its own whose icon states it
    /// while it is set, and the empty state offers to widen it by name. A reader can see that
    /// one without opening a menu, which is the whole test the count exists to pass. Android
    /// draws the same line in `narrowingCount`.
    var activeCount: Int {
        query.activeFilterCount + (isScoped ? 1 : 0) + (downloads.isActive ? 1 : 0)
    }

    /// Whether anything in the filter control is hiding part of the library.
    var isActive: Bool { activeCount > 0 }

    /// Every filter off, the library back to all of it.
    ///
    /// One action, everything it undoes — the library narrowing included, which is the whole
    /// point. Availability goes back to *Everywhere* with the rest: a *Clear filters* that
    /// left the shelf showing only what is on this device would leave it as empty as it found
    /// it, which is the state the requirement forbids showing silently.
    ///
    /// The sort, the layout and the search are untouched. The search has its own parameter
    /// because the two callers differ and the difference is deliberate: the filter menu
    /// clears filters while the reader is still looking at their results, and the
    /// narrowed-to-nothing state is offering to undo everything that could be hiding a match.
    func cleared(includingSearch: Bool = false) -> LibraryNarrowing {
        var cleared = self
        cleared.query = query.withoutFilters
        cleared.query.scope = .allSources
        if includingSearch { cleared.query.search = "" }
        cleared.downloads = .either
        cleared.availability = .everywhere
        return cleared
    }

    /// The libraries worth putting in front of a reader, or nothing at all.
    ///
    /// Empty below two libraries: a group offering "Any library" and the one there is asks a
    /// question with a single answer. Android gates its own `LIBRARY` section on
    /// `registry.sources.size > 1`, and `SourceRegistry.attributesPublications` is that same
    /// gate already written down — which is what keeps the filter menu and the shelf's own
    /// "does a publication state its source" rule from drifting apart.
    ///
    /// The registry's own order, because `SourceRegistry.scopes` makes that order meaningful
    /// and a selector that reshuffled it would undo an arrangement the reader made by hand.
    static func offeredLibraries(in registry: SourceRegistry) -> [LibraryScope] {
        registry.attributesPublications ? registry.scopes : []
    }
}
