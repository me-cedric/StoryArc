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
        #expect(content.contains("scroller.scrollTo(entry.publicationID, anchor: .top)"))
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
