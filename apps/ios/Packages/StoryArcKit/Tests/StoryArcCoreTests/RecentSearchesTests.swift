import Testing

@testable import StoryArcCore

/// The recent-search rules, asserted against the same table as Android's
/// `RecentSearchesTest`.
///
/// `library-browsing` offers recent queries when search opens, and two independent
/// implementations (ADR-0001) only stay honest if the same cases are put to both.
/// Add a case here, add it there.
@Suite("Recent searches")
struct RecentSearchesTests {

    @Test("The newest search is first")
    func newestFirst() {
        let searches = RecentSearches().recording("akira").recording("bone")
        #expect(searches.terms == ["bone", "akira"])
    }

    @Test("The same search twice is one row, spelled the way it was last typed")
    func duplicatesFold() {
        let searches = RecentSearches().recording("Bone").recording("akira").recording("bone")
        #expect(searches.terms == ["bone", "akira"])
    }

    @Test("A term that is only whitespace is not a search")
    func blankIsNotASearch() {
        #expect(RecentSearches().recording("   ").isEmpty)
    }

    @Test("The surrounding whitespace is not part of the term")
    func termIsTrimmed() {
        #expect(RecentSearches().recording("  bone ").terms == ["bone"])
    }

    @Test("A word typed one letter at a time is one search, not one per letter")
    func typingIsOneSearch() {
        var searches = RecentSearches()
        for term in ["m", "ma", "man", "mang", "manga"] {
            searches = searches.recording(term)
        }
        #expect(searches.terms == ["manga"])
    }

    @Test("Deleting a term back to nothing does not file the letters on the way out")
    func backspacingIsOneSearch() {
        let searches = RecentSearches().recording("manga").recording("mang").recording("m")
        #expect(searches.terms == ["manga"])
    }

    @Test("An older term that happens to be a prefix is left where it is")
    func onlyTheNewestFolds() {
        // "m" is a search of its own here: another search happened after it, so the
        // reader deliberately came back to it rather than passing through it.
        let searches = RecentSearches().recording("m").recording("bone").recording("manga")
        #expect(searches.terms == ["manga", "bone", "m"])
    }

    @Test("The list stops at its limit, and the oldest is what falls off")
    func limit() {
        var searches = RecentSearches()
        for index in 1...(RecentSearches.limit + 1) {
            searches = searches.recording("term \(index)")
        }
        #expect(searches.terms.count == RecentSearches.limit)
        #expect(searches.terms.first == "term \(RecentSearches.limit + 1)")
        #expect(!searches.terms.contains("term 1"))
    }
}
