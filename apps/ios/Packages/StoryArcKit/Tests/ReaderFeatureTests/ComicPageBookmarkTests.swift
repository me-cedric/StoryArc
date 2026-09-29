import Foundation
import Testing

import StoryArcCore
@testable import ReaderFeature

/// A page bookmark for a fixed-page publication (D8): the arithmetic and the locator
/// encoding, kept off `@MainActor` so a test can call them directly. Android's
/// `ComicPageBookmarkTest` asserts the same table.
@Suite("Comic page bookmark")
struct ComicPageBookmarkTests {

    @Test("Progression walks from 0 at the first page to 1 at the last")
    func progressionSpansTheWholePublication() {
        #expect(ComicPageBookmark.progression(forPage: 0, of: 5) == 0)
        #expect(ComicPageBookmark.progression(forPage: 4, of: 5) == 1)
        #expect(ComicPageBookmark.progression(forPage: 2, of: 5) == 0.5)
    }

    @Test("A single-page publication reports 0, not a division by zero")
    func singlePageIsZero() {
        #expect(ComicPageBookmark.progression(forPage: 0, of: 1) == 0)
    }

    @Test("A bookmark's own locator reads back the page it was made on")
    func pageIndexRoundTrips() throws {
        let annotation = Annotation(
            locator: "12",
            resource: "12",
            progression: 0.5,
            chapter: "",
            text: "Page 13",
            createdAt: Date()
        )
        #expect(ComicPageBookmark.pageIndex(of: annotation) == 12)
    }

    @Test("A locator this format did not write reads as no page at all")
    func foreignLocatorIsNil() {
        let pdfStyleAnnotation = Annotation(
            locator: #"{"page":2,"rects":[]}"#,
            resource: "3",
            progression: 0.5,
            chapter: "",
            text: "some words",
            createdAt: Date()
        )
        #expect(ComicPageBookmark.pageIndex(of: pdfStyleAnnotation) == nil)
    }

    @Test("A page already carrying a bookmark reads as bookmarked")
    func isBookmarkedFindsItsOwnPage() {
        let annotation = Annotation(
            locator: "3",
            resource: "3",
            progression: 0.3,
            chapter: "",
            text: "Page 4",
            createdAt: Date()
        )
        #expect(ComicPageBookmark.isBookmarked(3, among: [annotation]))
        #expect(!ComicPageBookmark.isBookmarked(4, among: [annotation]))
    }

    @Test("No bookmarks at all is never bookmarked")
    func emptyListIsNeverBookmarked() {
        #expect(!ComicPageBookmark.isBookmarked(0, among: []))
    }

    /// A tripwire over the view's source, the way `ReaderGestureTests` reads it: a live
    /// sheet cannot be dismissed on this host.
    @Test("Going to a bookmark closes the list, so the page it jumped to is in view")
    func goingToABookmarkClosesTheList() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/ReaderFeature/ComicBookmarkList.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
        let go = try #require(code.range(of: ".map(onGo)"))
        #expect(
            code[go.upperBound...].prefix(80).contains("dismiss()"),
            "A tap on a bookmark jumps behind a sheet that stays up."
        )
        #expect(code.contains("ToolbarItem(placement: .confirmationAction)"))
    }
}
