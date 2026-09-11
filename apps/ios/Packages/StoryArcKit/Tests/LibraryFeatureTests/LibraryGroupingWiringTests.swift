import Testing

@testable import LibraryFeature

/// That the grouping choice and the index are wired to the shelf, and are wired once.
///
/// Read as source for ``LibraryFeatureSource``'s reason: every claim here is a *declaration*
/// rather than a value — which branch the row set takes, which list the compact layout is
/// handed, whether the index is overlaid on one scroll reader or on three. A composition
/// reports what the inputs it was given drew, and the absence of a code path is not something
/// one composition settles.
struct LibraryGroupingWiringTests {

    private var content: String { LibraryFeatureSource.code(of: "Sources/LibraryFeature/LibraryContent.swift") }
    private var list: String { LibraryFeatureSource.code(of: "Sources/LibraryFeature/CoverList.swift") }
    private var menu: String { LibraryFeatureSource.code(of: "Sources/LibraryFeature/LibraryBrowsingControls.swift") }

    /// The third reason to take the flat branch, beside the search and the selection that
    /// were already there.
    @Test("The row set asks the grouping before it collapses anything")
    func rowsAskTheGrouping() {
        #expect(content.contains("guard grouping.isCollapsing, model.matchGroups.isEmpty, !selection.isActive"))
    }

    /// The parity this change settles. iOS handed the list `shown` and Android handed it the
    /// collapsed rows, so one platform listed issues whatever the reader chose and the other
    /// drew series rows that opened the first issue.
    @Test("The compact list is handed the same rows the grid is, and the same series map")
    func listTakesTheSameRows() {
        #expect(content.contains("CoverList("))
        #expect(!content.contains("publications: shown,\n                        groups: model.matchGroups"))
        #expect(content.contains("seriesRows: seriesRows"))
    }

    @Test("A list row standing for a series opens the series, not its first issue")
    func listRowOpensTheSeries() {
        #expect(list.contains("var series: (name: String, count: Int)?"))
        #expect(list.contains("openSeries(SeriesRoute(name: series.name))"))
        #expect(list.contains("NavigationLink(value: SeriesRoute(name: series.name))"))
    }

    /// One reader around the three branches, so a letter reaches a row in the sectioned grid,
    /// the plain grid and the `List` alike.
    @Test("The index is overlaid on one scroll reader")
    func oneScrollReader() {
        #expect(content.components(separatedBy: "ScrollViewReader").count == 2)
        #expect(content.contains("IndexRail(entries: rail)"))
        #expect(content.contains("scroller.scrollTo("))
    }

    /// **A letter lands on a heading, never behind one.** A pinned heading is drawn over the
    /// top of the scroll view, so the row a letter names has to be reached through the
    /// heading that names it — measured on Android, where 63 px of a 216 px row was hidden.
    /// The value itself is ``LibraryRailTests``' business; this states only that the jump
    /// asks for it, and that both headings carry the identifier it returns.
    @Test("A letter scrolls to the anchor the rail names")
    func theJumpAsksForTheAnchor() {
        let shelf = LibraryFeatureSource.code(of: "Sources/LibraryFeature/SectionedShelf.swift")
        #expect(content.contains("LibraryRail.anchors(sections: sections)[entry.publicationID]"))
        #expect(content.contains("?? entry.publicationID"))
        #expect(shelf.contains(".id(section.id)"), "the grid's heading is a scroll target")
        #expect(list.contains(".id(section.id)"), "the list's heading is a scroll target")
    }

    /// The second parity this file guards. The shelf divided in the grid and in no other
    /// layout, at any length, and `library-browsing`'s *Sectioning a long library* divides
    /// "the library" rather than the grid. The layout decides the column count and nothing
    /// else: three in the grid, one in the list, where a heading costs a single row.
    @Test("The compact list is handed the same headings, divided at one column")
    func listTakesTheSections() {
        #expect(content.contains("columns: model.layout == .list ? 1 : LibrarySections.coversPerRow"))
        #expect(
            content.components(separatedBy: "sections: sections,").count == 3,
            "the sectioned grid and the list both, and nothing else"
        )
        #expect(list.contains("var sections: [LibrarySection] = []"))
        #expect(list.contains("ForEach(sections) { section in"))
    }

    /// `library-browsing` asks for the choice inside the menu that holds the other view
    /// choices, and asks it to read as a grouping rather than as a sort.
    @Test("The choice is a named picker in the view menu")
    func pickerInTheViewMenu() {
        #expect(menu.contains("Picker(selection: $grouping)"))
        #expect(menu.contains("Text(\"library.grouping\", bundle: .module)"))
    }

    /// Every new string, in every language the app ships. `strings:ios` checks the catalogue
    /// as a whole; this names the five keys so a missing one fails where it was added.
    @Test("Five new strings, four languages each")
    func stringsAreTranslated() {
        for key in [
            "library.grouping",
            "library.grouping.series",
            "library.grouping.issues",
            "library.index",
            "library.index.jump %@",
        ] {
            let localizations = LibraryFeatureSource.localizationsIfAny(of: key)
            #expect(localizations != nil, "the catalogue does not answer \(key)")
            #expect(Set(localizations?.keys ?? [:].keys) == ["en", "fr", "de", "es"], "\(key)")
        }
    }
}
