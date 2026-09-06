import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The library files a title where the reader's language files it, not where the device does.
///
/// `localization` moves the interface into the language the reader chose. The override reaches
/// words and formatters and never reached collation: ``LibraryModel/rebuild()`` called
/// ``LibraryIndex/arrange(_:query:locale:progress:)`` with no locale, so the sort took
/// `Locale.current` — the *device's* language. A reader who set StoryArc to Spanish on a German
/// phone got German collation, and *ñ* filed where German files it.
///
/// The three languages below disagree about exactly this, and the disagreement is the assertion:
///
/// - Spanish makes *ñ* a letter of its own after *n*, so *Ñandú* follows *Nuez*.
/// - German folds *ä* and *å* onto *a*, so *Ñandú* precedes *Nuez* and both follow *Ähre*.
/// - Swedish puts *å* and *ä* after *z*, so *Ångström* and *Ähre* end the shelf.
///
/// Measured rather than assumed: the same five titles under `java.text.Collator` produce the
/// same three orders, so Android's `LibrarySortSpeaksTheReadersLanguageTest` holds this table
/// too and the two platforms cannot drift apart on it (ADR-0001).
///
/// **The choice is one value for the whole process, and `.serialized` does not fence it.**
/// `@MainActor` does, for the reason `ChosenLanguageFormattingTests` records: a main-actor
/// synchronous case runs to its end before the next one starts, wherever the next one lives.
@MainActor
@Suite("The library sorts in the reader's language", .serialized)
struct LibrarySortSpeaksTheReadersLanguageTests {

    // MARK: - Fixtures

    /// Five titles whose order differs in each of the three languages.
    ///
    /// One author on all five, so the search cases below reach every row at the same rank and
    /// the sort is what remains to decide their order.
    private static let titles = ["Zorro", "Ähre", "Nuez", "Ñandú", "Ångström"]

    private static let library: [Publication] = titles.map { title in
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            authors: ["Nordqvist"],
            origin: .inferred
        )
    }

    private static let inSpanish = ["Ähre", "Ångström", "Nuez", "Ñandú", "Zorro"]
    private static let inGerman = ["Ähre", "Ångström", "Ñandú", "Nuez", "Zorro"]
    private static let inSwedish = ["Ñandú", "Nuez", "Zorro", "Ångström", "Ähre"]

    /// The shelf as the model built it, for a reader who chose this language.
    private func shelf(readingIn language: String?) -> [String] {
        InterfaceLanguage.choose(language)
        defer { InterfaceLanguage.choose(nil) }
        let model = LibraryModel()
        model.publications = Self.library
        model.rebuild()
        return model.visible.map(\.displayTitle)
    }

    /// The search results as the model grouped them, flattened back into one order.
    private func results(readingIn language: String?) -> [String] {
        InterfaceLanguage.choose(language)
        defer { InterfaceLanguage.choose(nil) }
        let model = LibraryModel()
        model.publications = Self.library
        model.query = LibraryQuery(search: "nordqvist")
        return model.matchGroups.flatMap(\.publications).map(\.displayTitle)
    }

    // MARK: - The shelf

    @Test("A reader who chose Spanish gets Spanish collation, with ñ after n")
    func theShelfCollatesInSpanish() {
        #expect(shelf(readingIn: "es") == Self.inSpanish, "the shelf did not file ñ where Spanish files it")
    }

    /// **This case alone cannot catch the defect on an English host, and that is recorded
    /// rather than hidden.** English and German file these five titles identically, so a shelf
    /// that ignored the choice would pass here. The Spanish and Swedish cases are the ones that
    /// went red before the fix; this one states German's answer so the table is complete and so
    /// the case fails on a German host if the shelf ever stops asking.
    @Test("A reader who chose German gets German collation, with ä folded onto a")
    func theShelfCollatesInGerman() {
        #expect(shelf(readingIn: "de") == Self.inGerman, "the shelf did not file ä where German files it")
    }

    @Test("A reader who chose Swedish gets Swedish collation, with å and ä after z")
    func theShelfCollatesInSwedish() {
        #expect(shelf(readingIn: "sv") == Self.inSwedish, "the shelf did not file å where Swedish files it")
    }

    @Test("The three languages disagree, so passing any one of them is a real answer")
    func theThreeOrdersDiffer() {
        #expect(Set([Self.inSpanish, Self.inGerman, Self.inSwedish]).count == 3)
    }

    /// One shelf, two languages: the reader changes the setting and the shelf re-files itself.
    @Test("Changing the language reorders the shelf")
    func theShelfFollowsAChangeOfLanguage() {
        defer { InterfaceLanguage.choose(nil) }
        let model = LibraryModel()
        model.publications = Self.library

        InterfaceLanguage.choose("de")
        model.rebuild()
        let first = model.visible.map(\.displayTitle)

        InterfaceLanguage.choose("es")
        model.rebuild()
        let second = model.visible.map(\.displayTitle)

        #expect(first != second, "the shelf kept one order across two languages")
        #expect(first == Self.inGerman)
        #expect(second == Self.inSpanish)
    }

    // MARK: - Search results, which share the screen

    @Test("Search results are collated in the reader's language too")
    func searchResultsCollateInTheReadersLanguage() {
        #expect(results(readingIn: "es") == Self.inSpanish, "the search results ignored the chosen language")
        #expect(results(readingIn: "sv") == Self.inSwedish, "the search results ignored the chosen language")
    }

    // MARK: - A reading list's contents, which are the same shelf under another heading

    @Test("A reading list sorted by title collates in the reader's language")
    func aReadingListCollatesInTheReadersLanguage() {
        InterfaceLanguage.choose("sv")
        defer { InterfaceLanguage.choose(nil) }
        let entries = Self.library.map(\.id)
        let shown = ListOrdering.arrange(
            entries,
            by: ListOrder(sort: .title),
            publications: Self.library,
            locale: .storyArc
        )
        let titles = shown.map { id in Self.library.first { $0.id == id }?.displayTitle ?? id }
        #expect(titles == Self.inSwedish, "the reading list ignored the chosen language")
    }

    /// The one call site that draws a reading list, pinned as source.
    ///
    /// `CollectionDetail` and `ReadingListDetail` build the order inside a `View` body, which no
    /// value-level assertion reaches. The guard `LibraryFeatureSource` exists for is exactly
    /// this: the behaviour above proves the rule, and this proves the screen asks for it.
    @Test("The reading list screen hands the sort the reader's locale")
    func theReadingListScreenPassesTheReadersLocale() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/ShelfDetail.swift")
        #expect(code.contains("locale: .storyArc"), "ShelfDetail sorts in the device's language")
    }

    // MARK: - The iPad sidebar, which shares a screen with the shelf

    /// Two series whose order is the language's answer rather than the alphabet's.
    private static let withSeries: [Publication] = ["Nube", "Ñu"].map { name in
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(name) #1.cbz"),
            format: .cbz,
            displayTitle: "\(name) #1",
            series: name,
            origin: .inferred
        )
    }

    /// The sidebar's series column collates the way the shelf beside it collates.
    ///
    /// On an iPad the column and the shelf are on screen together, so two lists of the same
    /// names in opposite orders is a thing a reader sees at once. Spanish makes *ñ* a letter
    /// after *n* and files *Nube* first; German folds it onto *n* and files *Ñu* first, because
    /// *ñu* and *nub* agree until *ñu* runs out. `localizedStandardCompare` gave the second
    /// answer whatever the reader had chosen, because it resolves against the device.
    @Test("The sidebar's series list collates in the reader's language")
    func theSidebarCollatesInTheReadersLanguage() {
        InterfaceLanguage.choose("es")
        defer { InterfaceLanguage.choose(nil) }
        let inSpanish = SidebarSeriesList.series(in: Self.withSeries, locale: .storyArc)
        #expect(inSpanish.map(\.name) == ["Nube", "Ñu"], "the sidebar ignored the chosen language")

        InterfaceLanguage.choose("de")
        let inGerman = SidebarSeriesList.series(in: Self.withSeries, locale: .storyArc)
        #expect(inGerman.map(\.name) == ["Ñu", "Nube"], "the sidebar ignored the chosen language")
    }

    /// Three series, so a disagreement about *Ñandú* has somewhere to show.
    private static let threeSeries: [Publication] = ["Nube", "Ñandú", "Nuez"].map { name in
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(name) #1.cbz"),
            format: .cbz,
            displayTitle: "\(name) #1",
            series: name,
            origin: .inferred
        )
    }

    /// The column and the grid put *Ñandú* in the same place, on the screen that draws both.
    ///
    /// The two orders were asserted separately above and on their own that is not the property
    /// the reader sees. An iPad draws the sidebar beside the shelf, so what is wrong when they
    /// disagree is the *disagreement*, and a case that pins each list against its own table
    /// stays green while both drift together. This one compares the two lists to each other, so
    /// it fails whichever side moves.
    @Test("The sidebar and the shelf beside it file a series in the same place")
    func theSidebarAndTheShelfAgree() {
        InterfaceLanguage.choose("es")
        defer { InterfaceLanguage.choose(nil) }

        let model = LibraryModel()
        model.publications = Self.threeSeries
        model.query = LibraryQuery(sort: .series)
        model.rebuild()

        let onTheShelf = model.visible.compactMap(\.series)
        let inTheColumn = SidebarSeriesList.series(in: Self.threeSeries, locale: .storyArc).map(\.name)

        #expect(inTheColumn == ["Nube", "Nuez", "Ñandú"], "the column is not in Spanish order")
        #expect(onTheShelf == inTheColumn, "the sidebar and the shelf file a series differently")
    }

    // MARK: - The shell, which is where a language change happens

    /// The shell re-files the shelf when the reader changes the language.
    ///
    /// ``LibraryModel/visible`` is stored, not computed, and `rebuild()` is its only writer.
    /// None of `rebuild()`'s other callers is a language change: they are a query change, a
    /// progress refresh, a scan, an import, a download, a source edit, a folder watch and a
    /// cover cache. So a reader who picks *Español* watched every word around the grid turn
    /// Spanish while the grid kept the old language's order — until a scan, an import or a
    /// touch on a sort control happened to rebuild it. `localization` requires the whole
    /// interface to switch "immediately without a restart", and the shelf is interface.
    ///
    /// Android re-files it because choosing a language calls `recreate()`, and the activity
    /// coming back runs `refreshProgress()`, which rebuilds. `speaking(_:)` is iOS's whole
    /// equivalent and it changes no view identity, so nothing on this platform re-ran. The
    /// shell has to name the moment, and a `View` body is not something a value-level
    /// assertion reaches — ``ReaderRoutingWiringTests`` states at length why a guard on the
    /// app's wiring reads it as text.
    @Test("The shell re-files the shelf when the reader changes the language")
    func theShellRefilesTheShelfOnALanguageChange() {
        let code = LibraryFeatureSource.appCode(of: "App/StoryArcApp.swift")
        #expect(
            code.contains(".onChange(of: settings.language) { library.languageChanged() }"),
            "StoryArcApp keeps the old collation when the reader changes the language"
        )
    }

    // MARK: - The default, which must stay the process locale

    @Test("A caller that names no locale still gets the process locale")
    func theDefaultIsStillTheProcessLocale() {
        InterfaceLanguage.choose("sv")
        defer { InterfaceLanguage.choose(nil) }
        let query = LibraryQuery()
        let byDefault = LibraryIndex.arrange(Self.library, query: query).map(\.displayTitle)
        let byProcess = LibraryIndex.arrange(Self.library, query: query, locale: .current).map(\.displayTitle)
        #expect(byDefault == byProcess, "the default locale followed the reader instead of the process")
    }
}
