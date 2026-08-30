import Foundation
import Testing

import Catalogue
@testable import LibraryFeature

/// Where a catalogue search goes, and what it keeps when it cannot go anywhere.
///
/// `opds-catalog`: "searching within that source queries the server rather than filtering
/// locally", and "a catalogue without search falls back to filtering the cached catalogue,
/// and says so". Two decisions: which address a term becomes, and which entries a term
/// keeps. Neither had a test on either platform, and the Android half of the feature did
/// not exist at all.
///
/// The `CatalogueBrowser` itself is not built here. Android's is an `AndroidViewModel` that
/// a JVM unit test cannot construct — the same limit `SourceRemovalTests` records — so what
/// is asserted on both sides is the pair of pure decisions underneath it.
///
/// Android's `CatalogueSearchTest` asserts these cases in this order.
/// `@MainActor` because `CatalogueBrowser` is: the browser holds view state, and `fill` is
/// a static member of it rather than a free function.
@MainActor
@Suite("Catalogue search")
struct CatalogueSearchTests {

    // MARK: Where a term goes

    @Test("An OpenSearch template takes the term")
    func openSearchTemplate() {
        let filled = CatalogueBrowser.fill("https://books.example/search?q={searchTerms}", with: "bone")
        #expect(filled?.absoluteString == "https://books.example/search?q=bone")
    }

    @Test("The four spellings an OPDS 2.0 template uses are all substituted",
          arguments: ["{query}", "{?query}", "{q}", "{?q}"])
    func everySpelling(placeholder: String) {
        let filled = CatalogueBrowser.fill("https://books.example/s?t=\(placeholder)", with: "bone")
        #expect(filled?.absoluteString == "https://books.example/s?t=bone")
    }

    @Test("A space becomes %20, not a plus")
    func aSpace() {
        let filled = CatalogueBrowser.fill("https://books.example/s?q={searchTerms}", with: "sandman ouverture")
        #expect(filled?.absoluteString == "https://books.example/s?q=sandman%20ouverture")
    }

    @Test("A term outside ASCII is escaped by its bytes")
    func anAccent() {
        let filled = CatalogueBrowser.fill("https://books.example/s?q={searchTerms}", with: "épée")
        #expect(filled?.absoluteString == "https://books.example/s?q=%C3%A9p%C3%A9e")
    }

    @Test("The unreserved marks stand as written")
    func unreservedMarks() {
        let filled = CatalogueBrowser.fill("https://books.example/s?q={searchTerms}", with: "a-b_c.d*e")
        #expect(filled?.absoluteString == "https://books.example/s?q=a-b_c.d*e")
    }

    @Test("A template with no placeholder is not a search")
    func noPlaceholder() {
        // Substituting nothing would fetch the unfiltered feed and look like a search that
        // matched everything.
        #expect(CatalogueBrowser.fill("https://books.example/all", with: "bone") == nil)
    }

    // MARK: What a term keeps

    private func entry(
        title: String = "Bone",
        authors: [String] = ["Jeff Smith"],
        series: String? = "Bone"
    ) -> OpdsEntry {
        OpdsEntry(id: "1", title: title, authors: authors, series: series)
    }

    @Test("A title matches whatever case it was typed in")
    func aTitle() {
        #expect(entry(title: "The Sandman", authors: [], series: nil).matches("sandMAN"))
    }

    @Test("An author matches")
    func anAuthor() {
        #expect(entry(title: "Out From Boneville", authors: ["Jeff Smith"], series: nil).matches("smith"))
    }

    @Test("A series matches")
    func aSeries() {
        #expect(entry(title: "Volume One", authors: [], series: "Berserk").matches("berserk"))
    }

    @Test("An entry the term is nowhere in does not match")
    func noMatch() {
        #expect(!entry(title: "Bone", authors: ["Jeff Smith"], series: "Bone").matches("akira"))
    }
}
