public import CoreGraphics
public import Foundation
public import Observation

#if os(iOS)
internal import UIKit
#endif

public import Formats
internal import Persistence
public import StoryArcCore

/// A mark to draw over a page: where it is, and what colour the reader chose.
public struct PdfPageMark: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Normalised to the page, so it survives the raster being any size.
    public let rect: CGRect
    public let colour: HighlightColour
}

/// The text side of a PDF: what is selected, what is marked, and what a search found.
///
/// Its own model rather than more state on ``ReaderModel``, and for two reasons. The reader
/// model is the *pages* — the window of decoded images, the fit, the turn — and none of that
/// changes for a PDF that happens to carry text. And this exists only when there is text: a
/// scanned comic never builds one, which is what makes the absence of the controls structural
/// rather than a flag checked in every view.
///
/// `ebook-reader`: a PDF "contains a text layer" gets selection, in-publication search, and
/// the outline. All three are here; the reflowable half of the same requirements lives in
/// `EpubReaderModel`, over Readium, and the two share the record and the store rather than the
/// renderer.
///
/// Android's `PdfTextState` holds the same state.
@MainActor
@Observable
public final class PdfTextModel {

    /// What a mark's chapter is called for a PDF.
    ///
    /// A PDF's outline is a list of destinations, not a division of the text, so there is no
    /// chapter a locator falls "inside". The page is what a reader would name, and it is what
    /// the export groups under.
    public static func chapter(ofPage index: Int) -> String {
        String(localized: "reader.pdf.page \(index + 1)", bundle: .module, locale: .storyArc)
    }

    private let renderer: PdfPageRenderer
    private let store: AnnotationStore?
    private let publication: String
    private let pageCount: Int

    /// What the export document is headed with.
    public let title: String

    /// Everything the reader has marked in this publication, in reading order.
    public private(set) var annotations: [Annotation] = []

    /// The marks resolved to rectangles, per page, as pages come into view.
    ///
    /// Resolved lazily and kept: turning a locator back into rectangles opens the page in
    /// PDFKit, and doing that for four hundred marks when the reader opens the book would
    /// cost the whole document to draw three highlights.
    public private(set) var marks: [Int: [PdfPageMark]] = [:]

    /// What the reader has selected right now, or nothing.
    public private(set) var selection: PdfTextSelection?

    public private(set) var matches: [SearchMatch] = []
    public private(set) var isSearching = false

    /// Whether the run stopped at the cap rather than at the end of the document.
    public private(set) var isCapped = false

    /// The document's own navigation. Empty for a PDF that carries none.
    public private(set) var outline: [PdfOutlineItem] = []

    private var searchGeneration = 0
    private var selectionGeneration = 0

    init(
        renderer: PdfPageRenderer,
        store: AnnotationStore?,
        publication: String,
        title: String
    ) {
        self.renderer = renderer
        self.store = store
        self.publication = publication
        self.title = title
        self.pageCount = renderer.pageCount
    }

    /// Reads what is stored and the document's navigation. Called once, when the reader opens.
    public func load() async {
        annotations = store?.annotations(for: publication) ?? []
        outline = await renderer.outline()
    }

    // MARK: - Marks on the page

    /// The marks on one page, resolving them the first time that page is asked for.
    public func marks(onPage index: Int) -> [PdfPageMark] { marks[index] ?? [] }

    /// Turns this page's stored marks into rectangles, if it has not already.
    public func resolveMarks(onPage index: Int) async {
        guard marks[index] == nil else { return }
        marks[index] = await rects(onPage: index)
    }

    private func rects(onPage index: Int) async -> [PdfPageMark] {
        var found: [PdfPageMark] = []
        for annotation in annotations {
            guard let locator = PdfLocator(json: annotation.locator), locator.page == index,
                  let resolved = await renderer.selection(for: locator)
            else { continue }
            found += resolved.rects.map {
                PdfPageMark(id: annotation.id, rect: $0, colour: annotation.colour)
            }
        }
        return found
    }

    /// Draws every page's marks again, because one of them changed.
    private func redraw() async {
        let pages = Set(marks.keys)
        for page in pages { marks[page] = await rects(onPage: page) }
    }

    // MARK: - Selecting

    /// Selects what lies between two points, both normalised to the page.
    ///
    /// A drag asks for one of these per movement and each waits on the renderer, so the
    /// answers can arrive in a different order from the questions — an actor makes no promise
    /// about that. The generation is what stops an older answer landing on top of a newer one
    /// and leaving the mark a few words behind the finger.
    public func select(onPage index: Int, from: CGPoint, to: CGPoint) async {
        selectionGeneration += 1
        let generation = selectionGeneration
        let found = await renderer.selection(onPage: index, from: from, to: to)
        guard generation == selectionGeneration else { return }
        selection = found
    }

    public func clearSelection() {
        // Bumped, so a selection still in flight does not arrive after the reader dropped it.
        selectionGeneration += 1
        selection = nil
    }

    /// Puts the selected words on the pasteboard. One of the four the spec names.
    public func copySelection() {
        guard let selection else { return }
        #if os(iOS)
        UIPasteboard.general.string = selection.text
        #endif
        clearSelection()
    }

    // MARK: - Marking

    /// Marks the current selection in a colour, and hands back the mark it made.
    ///
    /// Handed back rather than looked up again, because writing a note on it is the very next
    /// thing a reader may do and a list search for "the one just added" is a lookup by luck.
    @discardableResult
    public func highlight(_ colour: HighlightColour) async -> Annotation? {
        guard let store, let selection else { return nil }
        let mark = Annotation(
            locator: selection.locator.json,
            resource: String(selection.locator.page + 1),
            progression: pageCount > 0
                ? Double(selection.locator.page) / Double(pageCount)
                : 0,
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
    public func annotate(_ annotation: Annotation, with note: String) async {
        guard let store else { return }
        annotations = store.save(
            Annotation(
                id: annotation.id,
                locator: annotation.locator,
                resource: annotation.resource,
                progression: annotation.progression,
                chapter: annotation.chapter,
                text: annotation.text,
                colour: annotation.colour,
                note: note,
                createdAt: annotation.createdAt
            ),
            in: publication
        )
        await redraw()
    }

    public func remove(_ id: UUID) async {
        guard let store else { return }
        annotations = store.remove(id, from: publication)
        await redraw()
    }

    /// The page a mark is on, so tapping its row turns there.
    public func page(of annotation: Annotation) -> Int? {
        PdfLocator(json: annotation.locator)?.page
    }

    // MARK: - Searching

    /// Searches the whole publication, page by page.
    ///
    /// A page at a time rather than the document at once, and that is not an optimisation: the
    /// renderer is an actor, so a walk that took it for the length of a five-hundred-page
    /// document would stall every page decode behind it. Between pages the reader can turn,
    /// and the results arrive as they are found — a reader looking for a word they know is on
    /// page nine should not wait for page four hundred.
    ///
    /// A new search replaces the one before it. The field is searched as it is typed, and a
    /// previous query still filling the list would put its results under the new one's.
    public func search(_ query: String) async {
        searchGeneration += 1
        let generation = searchGeneration

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matches = []
            isSearching = false
            isCapped = false
            return
        }

        matches = []
        isCapped = false
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }

        var found: [SearchMatch] = []
        for page in 0..<pageCount {
            guard generation == searchGeneration else { return }
            guard found.count < PdfTextSearch.matchLimit else {
                isCapped = true
                return
            }
            guard let text = await renderer.text(at: page) else { continue }
            guard generation == searchGeneration else { return }

            // The running count is read before the append rather than inside it: two
            // overlapping accesses to one array is a compile error, and the row identity has
            // to be the position in the whole run rather than in this page's share of it.
            let base = found.count
            let chapter = Self.chapter(ofPage: page)
            found += PdfTextSearch.matches(
                in: text,
                page: page,
                query: trimmed,
                limit: PdfTextSearch.matchLimit - base
            ).enumerated().map { offset, hit in
                SearchMatch(
                    id: base + offset,
                    locator: hit.locator.json,
                    chapter: chapter,
                    snippet: hit.snippet
                )
            }
            matches = found
        }
    }

    /// The page a hit is on, so tapping its row turns there.
    public func page(of match: SearchMatch) -> Int? {
        PdfLocator(json: match.locator)?.page
    }
}
