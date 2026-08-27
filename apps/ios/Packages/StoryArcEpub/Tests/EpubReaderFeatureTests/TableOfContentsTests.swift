import Foundation
import Testing

import ReadiumShared
import StoryArcCore
@testable import EpubReaderFeature

/// Which navigation entry owns the reader's place, and when none of them does.
///
/// The second half is the one worth a test. A publication whose whole text is one
/// content document lists every chapter as an anchor in that document, and matching on
/// the resource alone then marks the first chapter wherever the reader actually is.
/// Android's `indexOfResource` applies the same rule.
@MainActor
@Suite("EPUB table of contents")
struct TableOfContentsTests {

    /// A model with no publication opened. Nothing here needs one: the flattening and
    /// the matching are decisions about `Link` values and a locator, and opening a real
    /// EPUB to reach them would test Readium rather than this.
    private func model(at href: String?) -> EpubReaderModel {
        let reader = EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: "/nowhere.epub"),
                format: .epub,
                displayTitle: "nowhere",
                origin: .embedded
            ),
            url: URL(fileURLWithPath: "/nowhere.epub")
        )
        if let href, let url = AnyURL(string: href) {
            reader.locator = Locator(href: url, mediaType: .xhtml)
        }
        return reader
    }

    private func entries(_ hrefs: [String]) -> [ContentsEntry] {
        hrefs.enumerated().compactMap { index, href in
            guard let url = AnyURL(string: href) else { return nil }
            return ContentsEntry(
                id: index,
                title: href,
                depth: 0,
                link: ReadiumShared.Link(href: href),
                resource: url.removingQuery().removingFragment().string,
                isAnchor: url.fragment != nil
            )
        }
    }

    @Test("An entry that points at the whole resource owns it")
    func wholeResourceOwnsIt() {
        let reader = model(at: "OEBPS/ch2.xhtml")
        let rows = entries(["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])

        #expect(reader.currentEntry(in: rows) == 1)
    }

    @Test("A resource the navigation never names marks nothing")
    func unnamedResourceMarksNothing() {
        let reader = model(at: "OEBPS/afterword.xhtml")
        let rows = entries(["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])

        #expect(reader.currentEntry(in: rows) == nil)
    }

    @Test("A single-document book marks nothing rather than marking its first chapter")
    func singleDocumentMarksNothing() {
        // Every entry is an anchor in one file. Nothing in a locator says which anchor the
        // reader has scrolled past, so a mark here would be wrong everywhere — and a mark
        // that is wrong everywhere is worse than none, because nobody can tell which.
        let reader = model(at: "book.xhtml")
        let rows = entries(["book.xhtml#ch1", "book.xhtml#ch2", "book.xhtml#ch3"])

        #expect(reader.currentEntry(in: rows) == nil)
    }

    @Test("No locator marks nothing, rather than guessing at the first row")
    func noLocatorMarksNothing() {
        let reader = model(at: nil)

        #expect(reader.currentEntry(in: entries(["OEBPS/ch1.xhtml"])) == nil)
    }

    @Test("A query on the locator does not stop it matching")
    func queryIsIgnored() {
        let reader = model(at: "OEBPS/ch1.xhtml?v=2")
        let rows = entries(["OEBPS/ch1.xhtml"])

        #expect(reader.currentEntry(in: rows) == 0)
    }
}
