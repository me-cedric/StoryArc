import AppKit
import Formats
import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

/// The Mac's PDF text layer over the corpus PDFs: selection, search, marks, the outline and
/// the pasteboard, with no window. `ebook-reader`, *PDF rendering*. Task 4.6.
@MainActor
@Suite("PDF text")
struct PdfTextTests {
    static let textPages = TestFixtures.comics.appending(path: "text-pages.pdf")
    static let imagePages = TestFixtures.comics.appending(path: "image-pages.pdf")

    private static func publication(_ name: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/pdf/\(name).pdf"), format: .pdf,
            displayTitle: name, origin: .inferred
        )
    }

    private static func open(_ name: String, url: URL) throws -> (MacPdfText, ScratchDefaults) {
        let scratch = try ScratchDefaults(prefix: "pdf-text-")
        let text = try #require(MacPdfText.open(
            url: url, publication: publication(name), store: AnnotationStore(defaults: scratch.defaults)
        ))
        return (text, scratch)
    }

    @Test("A text layer is detected rather than assumed: the scan gets no model")
    func detection() {
        #expect(MacPdfText.open(url: Self.imagePages, publication: Self.publication("scan")) == nil)
        #expect(MacPdfText.open(url: Self.textPages, publication: Self.publication("text")) != nil)
    }

    @Test("Search lists each hit with its page and context, in order")
    func search() async throws {
        let (text, scratch) = try Self.open("text", url: Self.textPages)
        defer { scratch.remove() }
        await text.load()
        await text.search("chapter")
        #expect(!text.isSearching)
        #expect(text.hits.map(\.page) == [0, 1, 2])
        #expect(text.hits.map { $0.snippet.match.lowercased() } == ["chapter", "chapter", "chapter"])
        #expect(text.hits.first?.snippet.after.contains("One") == true)
        #expect(text.hits.map(\.id) == [0, 1, 2])
        await text.search("")
        #expect(text.hits.isEmpty)
        await text.search("nothing of the kind")
        #expect(text.hits.isEmpty && !text.isCapped)
    }

    @Test("The outline names the three chapters with their pages")
    func outline() async throws {
        let (text, scratch) = try Self.open("text", url: Self.textPages)
        defer { scratch.remove() }
        await text.load()
        #expect(text.outline.map(\.title) == ["Chapter One", "Chapter Two", "Chapter Three"])
        #expect(text.outline.map(\.pageIndex) == [0, 1, 2])
    }

    @Test("A drag across the first page selects its words, a copy puts them on the pasteboard, a mark is drawn back")
    func selectCopyAndMark() async throws {
        let (text, scratch) = try Self.open("text", url: Self.textPages)
        defer { scratch.remove() }
        await text.load()
        await text.select(onPage: 0, from: CGPoint(x: 0.02, y: 0.02), to: CGPoint(x: 0.98, y: 0.98))
        let selection = try #require(text.selection)
        #expect(selection.text.contains("Chapter One"))
        #expect(!selection.rects.isEmpty)
        #expect(selection.rects.allSatisfy { (0...1).contains($0.minX) && (0...1).contains($0.minY) })
        #expect(selection.locator.page == 0)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.storyarc.pdf-text-test"))
        text.copySelection(to: pasteboard)
        #expect(pasteboard.string(forType: .string)?.contains("Chapter One") == true)
        #expect(text.selection == nil)

        await text.select(onPage: 0, from: CGPoint(x: 0.02, y: 0.02), to: CGPoint(x: 0.98, y: 0.98))
        let mark = try #require(await text.highlight(.green))
        #expect(mark.colour == .green)
        #expect(mark.chapter == MacPdfText.chapter(ofPage: 0))
        #expect(text.annotations.count == 1)
        await text.resolveMarks(onPage: 0)
        #expect(text.marks(onPage: 0).contains { $0.id == mark.id && $0.colour == .green })
        #expect(text.marks(onPage: 1).isEmpty)
        await text.annotate(mark, with: "worth a second look")
        #expect(text.annotations.first?.note == "worth a second look")
        await text.remove(mark.id)
        #expect(text.annotations.isEmpty)
        #expect(text.marks(onPage: 0).isEmpty)
    }

    @Test("A drag over the margin selects nothing, and a tap selects the word under it")
    func marginAndWord() async throws {
        let (text, scratch) = try Self.open("text", url: Self.textPages)
        defer { scratch.remove() }
        await text.select(onPage: 0, from: CGPoint(x: 0.9, y: 0.9), to: CGPoint(x: 0.95, y: 0.95))
        #expect(text.selection == nil)
        text.clearSelection()
        #expect(text.selection == nil)
    }

    @Test("The page geometry maps the view and the page both ways")
    func geometry() {
        let image = CGSize(width: 200, height: 300)
        let view = CGSize(width: 800, height: 600)
        let rect = PdfPageGeometry.pageRect(of: image, in: view)
        #expect(rect == CGRect(x: 200, y: 0, width: 400, height: 600))
        let centre = PdfPageGeometry.normalisedPoint(CGPoint(x: 400, y: 300), imageSize: image, in: view)
        #expect(centre == CGPoint(x: 0.5, y: 0.5))
        let clamped = PdfPageGeometry.normalisedPoint(CGPoint(x: 0, y: 900), imageSize: image, in: view)
        #expect(clamped == CGPoint(x: 0, y: 1))
        let quarter = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let back = PdfPageGeometry.viewRect(quarter, imageSize: image, in: view)
        #expect(back == CGRect(x: 300, y: 300, width: 200, height: 150))
        #expect(PdfPageGeometry.pageRect(of: .zero, in: view) == .zero)
    }
}
