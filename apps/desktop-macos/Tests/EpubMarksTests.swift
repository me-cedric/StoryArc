import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// Bookmarks, highlights, notes and footnotes in an EPUB (`ebook-reader`, *Bookmarks*, *Highlights and notes*,
/// *Following an internal link*), over the phones' stores in a defaults suite of their own.
@MainActor
@Suite("EPUB marks")
struct EpubMarksTests {
    private let locator = #"{"href":"OEBPS/ch1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.25}}"#

    private func marks() throws -> EpubMarks {
        let defaults = try #require(UserDefaults(suiteName: "marks-\(UUID().uuidString)"))
        return EpubMarks(publicationID: "book", defaults: defaults)
    }

    @Test("A bookmark is added at a place and the same place removes it")
    func bookmarkToggles() throws {
        let marks = try marks()
        let place = EpubPlace(locator: locator, chapter: "One")
        #expect(place.resource == "OEBPS/ch1.xhtml")
        #expect(place.progression == 0.25)
        marks.toggleBookmark(at: place)
        #expect(marks.bookmarks.count == 1)
        #expect(marks.bookmark(at: place)?.chapter == "One")
        marks.toggleBookmark(at: place)
        #expect(marks.bookmarks.isEmpty)
    }

    @Test("A selection becomes a highlight in its colour, takes a note, and is drawn by one message")
    func selectionHighlights() throws {
        let marks = try marks()
        marks.receive("selection", ["text": " the quick fox ", "locator": ["href": "OEBPS/ch1.xhtml"]])
        #expect(marks.selection?.text == "the quick fox")
        let made = try #require(marks.highlightSelection(.green, chapter: "One"))
        #expect(marks.selection == nil)
        #expect(made.colour == .green)
        marks.setNote("remember this", on: made.id)
        #expect(marks.annotations.first?.note == "remember this")
        #expect(marks.highlightsJSON.contains("\"color\":\"green\""))
        #expect(marks.highlightsJSON.contains(made.id.uuidString))
        marks.receive("highlight-activated", ["id": made.id.uuidString])
        #expect(marks.activated?.id == made.id)
        marks.removeHighlight(made.id)
        #expect(marks.annotations.isEmpty)
        #expect(marks.activated == nil)
    }

    @Test("An empty selection raises nothing, and a footnote is held to be shown in place")
    func emptySelectionAndFootnote() throws {
        let marks = try marks()
        marks.receive("selection", ["text": "   "])
        #expect(marks.selection == nil)
        marks.receive("footnote", ["href": "#n1", "text": "A note."])
        #expect(marks.footnote == EpubFootnote(href: "#n1", text: "A note."))
    }
}

/// A link the reader followed inside the book leaves a way back (`ebook-reader`, *Following an internal link*).
@MainActor
@Suite("EPUB jumps")
struct EpubJumpTests {
    @Test("A chapter change the app did not ask for keeps the place it left; one it asked for does not")
    func linkLeavesAWayBack() {
        let model = EpubReaderModel(
            target: ReaderTarget(publicationID: "jump", path: "/tmp/jump.epub", title: "Jump"),
            publication: Publication(
                identity: .init(normalizedPath: "/tmp/jump.epub"), format: .epub,
                displayTitle: "Jump", origin: .inferred
            ),
            progress: nil
        )
        model.receive(["type": "locator", "locator": ["href": "OEBPS/ch1.xhtml", "locations": ["position": 1]]])
        model.receive(["type": "locator", "locator": ["href": "OEBPS/ch2.xhtml", "locations": ["position": 2]]])
        #expect(model.returnLocator?.contains("ch1.xhtml") == true)

        model.returnLocator = nil
        model.next()
        model.receive(["type": "locator", "locator": ["href": "OEBPS/ch3.xhtml", "locations": ["position": 3]]])
        #expect(model.returnLocator == nil)
    }

    @Test("A link out of the book waits for its host to be confirmed; any scheme but http and https is dropped")
    func linkOutWaits() {
        var opened: [URL] = []
        let saved = EpubLinkOpener.open
        EpubLinkOpener.open = { opened.append($0) }
        defer { EpubLinkOpener.open = saved }
        #expect(EpubReaderModel.outward("https://example.org/a")?.host() == "example.org")
        #expect(EpubReaderModel.outward("HTTP://example.org") != nil)
        #expect(EpubReaderModel.outward("mailto:someone@example.org") == nil)
        #expect(EpubReaderModel.outward("javascript:alert(1)") == nil)
        #expect(EpubReaderModel.outward("file:///etc/hosts") == nil)
        #expect(EpubReaderModel.outward(nil) == nil)
        #expect(opened.isEmpty, "nothing opens before the reader says yes")
    }

    @Test("The sentence being spoken joins the highlights message as its own decoration, found by its text")
    func spokenDecoration() throws {
        let locator = try #require(EpubMarks.spokenLocator("It began.", href: "OEBPS/ch1.xhtml"))
        #expect(locator.contains("\"highlight\":\"It began.\""))
        let defaults = try #require(UserDefaults(suiteName: "spoken-\(UUID())"))
        let marks = EpubMarks(publicationID: "spoken", defaults: defaults)
        #expect(marks.highlightsJSON(spoken: locator).contains("\"id\":\"spoken\""))
        #expect(!marks.highlightsJSON.contains("spoken"))
    }
}
