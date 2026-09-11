import Testing

@testable import LibraryFeature

/// The two answers the shelf can give about a series, and what is written down for each.
///
/// `library-browsing`'s *The choice between series and issues* scenario asks for the choice
/// to persist across visits and for series to be the answer a reader who never chose gets.
/// Android's `LibraryGroupingTest` answers the same cases.
struct LibraryGroupingTests {

    @Test("Series collapses, issues does not")
    func collapsing() {
        #expect(LibraryGrouping.series.isCollapsing)
        #expect(!LibraryGrouping.issues.isCollapsing)
    }

    @Test("Series is offered first, so it is the answer a menu opens on")
    func seriesLeads() {
        #expect(LibraryGrouping.allCases.first == .series)
        #expect(LibraryGrouping.allCases.count == 2)
    }

    /// The stored value is the case name, never its position. A reordering of the enum would
    /// otherwise change what an already-stored preference means — the reason
    /// `LibraryPreferences` gives on Android for writing names rather than ordinals.
    @Test("Every case round-trips through its stored name")
    func storedNames() {
        for grouping in LibraryGrouping.allCases {
            #expect(LibraryGrouping(rawValue: grouping.rawValue) == grouping)
        }
        #expect(LibraryGrouping.series.rawValue == "series")
        #expect(LibraryGrouping.issues.rawValue == "issues")
    }

    @Test("An unreadable stored name is no answer, so the default stands")
    func unknownName() {
        #expect(LibraryGrouping(rawValue: "collapsed") == nil)
    }

    /// Three shelf choices, three keys. A shared key would have one control silently move
    /// another, which is the failure ``LibraryAvailability/searchScopeKey`` exists to avoid.
    @Test("The storage key is its own")
    func storageKey() {
        #expect(LibraryGrouping.storageKey == "app.storyarc.libraryGrouping")
        #expect(LibraryGrouping.storageKey != LibraryAvailability.storageKey)
        #expect(LibraryGrouping.storageKey != DownloadFilter.storageKey)
    }

    @Test("Each case names itself, and the two names differ")
    func titles() {
        #expect(LibraryGrouping.series.titleKey != LibraryGrouping.issues.titleKey)
    }
}
