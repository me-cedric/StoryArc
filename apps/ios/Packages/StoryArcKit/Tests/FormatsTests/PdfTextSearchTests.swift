import Foundation
import Testing

import StoryArcCore

@testable import Formats

/// Mirrors Android's `PdfTextSearchTest`, assertion for assertion.
///
/// Pure text, no PDF: what a page's text layer says is the platform's business, and what is
/// done with the string it hands over is this app's. Keeping the two apart is what lets the
/// snippet rule be asserted identically on both sides.
@Suite("PDF text search")
struct PdfTextSearchTests {

    private let page = "Chapter One\nThe sandman walked."

    @Test("A hit is reported with its page and its offsets")
    func reportsTheHit() {
        let found = PdfTextSearch.matches(in: page, page: 4, query: "sandman")
        #expect(found.count == 1)
        #expect(found.first?.locator == PdfLocator(page: 4, start: 16, end: 23))
    }

    @Test("Every occurrence on a page is reported, in reading order")
    func reportsEveryOccurrence() {
        let found = PdfTextSearch.matches(in: "one two one", page: 0, query: "one")
        #expect(found.map(\.locator.start) == [0, 8])
    }

    @Test("The search is case-insensitive, because a search box is not a grep")
    func ignoresCase() {
        #expect(PdfTextSearch.matches(in: page, page: 0, query: "SANDMAN").count == 1)
    }

    @Test("A word that is not on the page yields nothing")
    func findsNothing() {
        #expect(PdfTextSearch.matches(in: page, page: 0, query: "dreaming").isEmpty)
    }

    @Test("An empty query yields nothing rather than every position")
    func emptyQuery() {
        #expect(PdfTextSearch.matches(in: page, page: 0, query: "").isEmpty)
    }

    @Test("The limit caps the run")
    func capsTheRun() {
        #expect(PdfTextSearch.matches(in: "aaaa", page: 0, query: "aa", limit: 1).count == 1)
    }

    @Test("Overlapping runs are reported once each, not once per position")
    func doesNotOverlap() {
        let found = PdfTextSearch.matches(in: "aaaa", page: 0, query: "aa")
        #expect(found.map(\.locator.start) == [0, 2])
    }

    @Test("The snippet carries the words around the hit")
    func carriesContext() {
        let snippet = PdfTextSearch.matches(in: page, page: 0, query: "sandman").first?.snippet
        #expect(snippet?.before == "Chapter One The")
        #expect(snippet?.match == "sandman")
        #expect(snippet?.after == "walked.")
    }

    @Test("A page's own line breaks do not reach the row")
    func condensesLineBreaks() {
        let line = PdfTextSearch.matches(in: page, page: 0, query: "sandman").first?.snippet.line
        #expect(line == "Chapter One The sandman walked.")
    }

    @Test("Context is trimmed by the one snippet rule, not by a second one")
    func trimsByTheSnippetRule() {
        let long = String(repeating: "word ", count: 60)
        let snippet = PdfTextSearch.matches(
            in: long + "sandman " + long, page: 0, query: "sandman"
        ).first?.snippet
        // The budget, split between two sides that both had more to give.
        #expect((snippet?.before.count ?? 0) <= SearchSnippet.budget / 2)
        #expect((snippet?.after.count ?? 0) <= SearchSnippet.budget / 2)
    }

    @Test("The offsets point into the untouched text, so the words read back")
    func offsetsReadBack() throws {
        let hit = try #require(PdfTextSearch.matches(in: page, page: 0, query: "sandman").first)
        #expect(PdfTextSearch.text(hit.locator, in: page) == "sandman")
    }

    @Test("A locator that names nothing in the text reads back as nothing")
    func offsetsOutOfRange() {
        #expect(PdfTextSearch.text(PdfLocator(page: 0, start: 900, end: 950), in: page) == nil)
        #expect(PdfTextSearch.text(PdfLocator(page: 0, start: 4, end: 4), in: page) == nil)
    }
}
