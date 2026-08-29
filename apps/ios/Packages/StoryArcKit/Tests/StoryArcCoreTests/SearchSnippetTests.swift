import Foundation
import Testing

@testable import StoryArcCore

/// Mirrors Android's `SearchSnippetTest`, assertion for assertion.
@Suite("Search snippets")
struct SearchSnippetTests {

    private let long = String(repeating: "word ", count: 60)

    @Test("The match survives whatever the budget is")
    func keepsTheMatch() {
        let snippet = SearchSnippet(before: long, match: "sandman", after: long, budget: 10)
        #expect(snippet.match == "sandman")
        #expect(snippet.line.contains("sandman"))
    }

    @Test("A match longer than the whole budget is still not cut")
    func keepsAnOversizedMatch() {
        let match = String(repeating: "x", count: 200)
        #expect(SearchSnippet(before: "a", match: match, after: "b", budget: 10).match == match)
    }

    @Test("Context is trimmed to the budget when both sides are long")
    func trimsBothSides() {
        let snippet = SearchSnippet(before: long, match: "m", after: long, budget: 40)
        #expect(snippet.before.count <= 20)
        #expect(snippet.after.count <= 20)
    }

    @Test("What one side does not use, the other may")
    func spendsTheSpareBudget() {
        // Nothing before the match, so the whole budget is available after it.
        let snippet = SearchSnippet(before: "", match: "m", after: long, budget: 40)
        #expect(snippet.before.isEmpty)
        #expect(snippet.after.count > 20)
    }

    @Test("Leading context keeps the words nearest the match, not the first ones")
    func keepsTheNearestWords() {
        let before = "alpha bravo charlie delta echo foxtrot"
        let snippet = SearchSnippet(before: before, match: "m", after: "", budget: 20)
        #expect(snippet.before.hasSuffix("foxtrot"))
        #expect(!snippet.before.contains("alpha"))
    }

    @Test("Trailing context keeps the words nearest the match")
    func keepsTheFollowingWords() {
        let after = "alpha bravo charlie delta echo foxtrot"
        let snippet = SearchSnippet(before: "", match: "m", after: after, budget: 20)
        #expect(snippet.after.hasPrefix("alpha"))
        #expect(!snippet.after.contains("foxtrot"))
    }

    @Test("A short context is left alone")
    func leavesShortContextAlone() {
        let snippet = SearchSnippet(before: "a short lead", match: "m", after: "a short tail")
        #expect(snippet.before == "a short lead")
        #expect(snippet.after == "a short tail")
    }

    @Test("The line reads as one sentence, with no gaps where a side was empty")
    func joinsIntoOneLine() {
        #expect(SearchSnippet(before: "", match: "m", after: "").line == "m")
        #expect(SearchSnippet(before: "a", match: "m", after: "").line == "a m")
        #expect(SearchSnippet(before: "", match: "m", after: "b").line == "m b")
    }

    @Test("Whitespace the renderer left on the context does not reach the row")
    func trimsWhitespace() {
        let snippet = SearchSnippet(before: "  lead \n", match: "m", after: "\n tail  ")
        #expect(snippet.before == "lead")
        #expect(snippet.after == "tail")
    }
}
