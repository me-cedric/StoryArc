import AppKit
import Formats
import Foundation
import Persistence
import StoryArcCore

/// A mark to draw over a page: where it is, in page space, and the colour the reader chose.
struct MacPdfMark: Sendable, Equatable, Identifiable {
    let id: UUID
    let rect: CGRect
    let colour: HighlightColour
}

/// One hit in the document, with its page for the jump.
struct MacPdfHit: Sendable, Equatable, Identifiable {
    let id: Int
    let page: Int
    let snippet: SearchSnippet
    let locator: PdfLocator
}

/// The PDF's text layer, read off the main actor.
///
/// `PDFDocument` is not `Sendable`, so the reader lives inside an actor and renders,
/// selections and searches serialise, as `ReaderFeature`'s `PdfPageRenderer` does for the
/// pages. That renderer is internal to the package, so the Mac has its own over the public
/// `PdfDocumentReader` (parent edit, task 1.30's family).
actor MacPdfLayer {
    private let reader: PdfDocumentReader
    nonisolated let pageCount: Int
    nonisolated let hasTextLayer: Bool

    init(url: URL) throws {
        reader = try PdfDocumentReader(url: url)
        pageCount = reader.pageCount
        hasTextLayer = reader.hasTextLayer
    }

    func text(at index: Int) -> String? { try? reader.text(at: index) }

    func selection(onPage index: Int, from: CGPoint, to: CGPoint) -> PdfTextSelection? {
        reader.selection(onPage: index, from: from, to: to)
    }

    func selection(for locator: PdfLocator) -> PdfTextSelection? { reader.selection(for: locator) }

    func outline() -> [PdfOutlineItem] { reader.outline }
}

/// The text side of a PDF on the Mac: what is selected, what is marked, what a search found,
/// and the document's own outline.
///
/// A port of `ReaderFeature`'s `PdfTextModel` to `NSPasteboard` and the Mac's pointer: the
/// package's model is internal and its pasteboard is UIKit's. It exists only when the file
/// has a text layer (`ebook-reader`, *A text layer is detected rather than assumed*), so the
/// controls are absent for a scan rather than disabled. The marks are the same `Annotation`
/// records in the same `AnnotationStore`, so a mark made here is listed and exported with
/// the EPUB reader's. Task 4.6.
@MainActor
@Observable
final class MacPdfText {
    let layer: MacPdfLayer
    let title: String
    private let store: AnnotationStore
    private let publication: String

    private(set) var annotations: [Annotation] = []
    private(set) var marks: [Int: [MacPdfMark]] = [:]
    private(set) var selection: PdfTextSelection?
    private(set) var hits: [MacPdfHit] = []
    private(set) var isSearching = false
    private(set) var isCapped = false
    private(set) var outline: [PdfOutlineItem] = []
    private var searchGeneration = 0
    private var selectionGeneration = 0

    /// The model for a file, or `nil` when it carries no text at all.
    static func open(url: URL, publication: Publication, store: AnnotationStore = AnnotationStore()) -> MacPdfText? {
        guard let layer = try? MacPdfLayer(url: url), layer.hasTextLayer else { return nil }
        return MacPdfText(layer: layer, store: store, publication: publication.id, title: publication.displayTitle)
    }

    init(layer: MacPdfLayer, store: AnnotationStore, publication: String, title: String) {
        self.layer = layer
        self.store = store
        self.publication = publication
        self.title = title
    }

    /// What a mark's chapter is called for a PDF: the page, which is what a reader would name.
    static func chapter(ofPage index: Int) -> String {
        String(localized: "desktop.pdf.page \(index + 1)", locale: .storyArc)
    }

    func load() async {
        annotations = store.annotations(for: publication)
        outline = await layer.outline()
    }

    // MARK: - Marks

    func marks(onPage index: Int) -> [MacPdfMark] { marks[index] ?? [] }

    func resolveMarks(onPage index: Int) async {
        guard marks[index] == nil else { return }
        marks[index] = await rects(onPage: index)
    }

    private func rects(onPage index: Int) async -> [MacPdfMark] {
        var found: [MacPdfMark] = []
        for annotation in annotations {
            guard let locator = PdfLocator(json: annotation.locator), locator.page == index,
                  let resolved = await layer.selection(for: locator)
            else { continue }
            found += resolved.rects.map { MacPdfMark(id: annotation.id, rect: $0, colour: annotation.colour) }
        }
        return found
    }

    private func redraw() async {
        for page in Set(marks.keys) { marks[page] = await rects(onPage: page) }
    }

    // MARK: - Selecting

    /// Selects what lies between two points, both in page space. Answers can come back out of
    /// order, so an older one never lands on a newer.
    func select(onPage index: Int, from: CGPoint, to: CGPoint) async {
        selectionGeneration += 1
        let generation = selectionGeneration
        let found = await layer.selection(onPage: index, from: from, to: to)
        guard generation == selectionGeneration else { return }
        selection = found
    }

    func clearSelection() {
        selectionGeneration += 1
        selection = nil
    }

    /// Puts the selected words on the pasteboard, as Edit > Copy would.
    func copySelection(to pasteboard: NSPasteboard = .general) {
        guard let selection else { return }
        pasteboard.clearContents()
        pasteboard.setString(selection.text, forType: .string)
        clearSelection()
    }

    // MARK: - Marking

    @discardableResult
    func highlight(_ colour: HighlightColour) async -> Annotation? {
        guard let selection else { return nil }
        let mark = Annotation(
            locator: selection.locator.json,
            resource: String(selection.locator.page + 1),
            progression: layer.pageCount > 0 ? Double(selection.locator.page) / Double(layer.pageCount) : 0,
            chapter: Self.chapter(ofPage: selection.locator.page),
            text: selection.text,
            colour: colour,
            createdAt: Date()
        )
        annotations = store.save(mark, in: publication)
        clearSelection()
        await redraw()
        return mark
    }

    /// Writes on a mark, or replaces what was written.
    func annotate(_ annotation: Annotation, with note: String) async {
        annotations = store.save(
            Annotation(
                id: annotation.id, locator: annotation.locator, resource: annotation.resource,
                progression: annotation.progression, chapter: annotation.chapter, text: annotation.text,
                colour: annotation.colour, note: note, createdAt: annotation.createdAt
            ),
            in: publication
        )
        await redraw()
    }

    func remove(_ id: UUID) async {
        annotations = store.remove(id, from: publication)
        await redraw()
    }

    func page(of annotation: Annotation) -> Int? { PdfLocator(json: annotation.locator)?.page }

    // MARK: - Searching

    /// Searches the document page by page; the results arrive as they are found and a new
    /// search replaces the one before it. Capped at `PdfTextSearch.matchLimit`, and says so.
    func search(_ query: String) async {
        searchGeneration += 1
        let generation = searchGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hits = []
        isCapped = false
        isSearching = !trimmed.isEmpty
        guard !trimmed.isEmpty else { return }
        defer { if generation == searchGeneration { isSearching = false } }
        var found: [MacPdfHit] = []
        for page in 0..<layer.pageCount {
            guard generation == searchGeneration else { return }
            guard found.count < PdfTextSearch.matchLimit else {
                isCapped = true
                return
            }
            guard let text = await layer.text(at: page), generation == searchGeneration else { continue }
            let base = found.count
            let limit = PdfTextSearch.matchLimit - base
            found += PdfTextSearch.matches(in: text, page: page, query: trimmed, limit: limit)
                .enumerated()
                .map { MacPdfHit(id: base + $0, page: page, snippet: $1.snippet, locator: $1.locator) }
            hits = found
        }
    }
}
