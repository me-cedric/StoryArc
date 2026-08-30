internal import CoreGraphics
internal import Foundation

internal import Formats

// Its own file rather than a private type at the foot of `ReaderModel`, because that
// file reached the 400-line cap and this is the seam that was already there: everything
// here is about PDFKit and nothing else in the reader is.

/// A PDF, rendered off the main actor.
///
/// `PDFDocument` is not `Sendable`, so the reader cannot be handed to a detached
/// task — Swift 6 rejects that outright, and it would be a real race rather than
/// a pedantic one. An actor owns the document instead: it is created inside the
/// actor and never leaves it, and renders serialise, which is what PDFKit wants
/// anyway.
actor PdfPageRenderer {
    private let reader: PdfDocumentReader

    /// Page count, read once. Cheap, and it saves an `await` per pager layout.
    nonisolated let pageCount: Int

    /// Whether this PDF carries text at all.
    ///
    /// Read once at open and held outside the actor, because it decides what the *chrome*
    /// offers: a control cannot wait on an `await` to know whether it should exist, and
    /// `ebook-reader` requires a text-dependent control to be absent rather than to appear
    /// and then fail.
    nonisolated let hasTextLayer: Bool

    init(url: URL) throws {
        let reader = try PdfDocumentReader(url: url)
        self.reader = reader
        self.pageCount = reader.pageCount
        self.hasTextLayer = reader.hasTextLayer
    }

    /// One page's text, or `nil` when it has none. What a search is run over.
    ///
    /// One optional, not two: `try?` flattens a throwing call that already returns one, so a
    /// page with no text and a page that could not be read arrive here the same way.
    func text(at index: Int) -> String? {
        try? reader.text(at: index)
    }

    /// What lies between two points on a page, both in normalised page space.
    func selection(onPage index: Int, from: CGPoint, to: CGPoint) -> PdfTextSelection? {
        reader.selection(onPage: index, from: from, to: to)
    }

    /// The words a stored mark names, so it can be drawn back onto the page.
    func selection(for locator: PdfLocator) -> PdfTextSelection? {
        reader.selection(for: locator)
    }

    /// The document's own navigation, empty when it carries none.
    ///
    /// PDFKit reads an outline and Android's PDF API exposes none, which is why this has no
    /// Kotlin mirror. ADR-0012.
    func outline() -> [PdfOutlineItem] { reader.outline }

    /// One page, rasterised at the size it will be drawn.
    ///
    /// `nil` rather than a throw: the reader shows a named "page unavailable"
    /// placeholder for a page it cannot produce, and one bad page in a PDF should
    /// not close the whole document.
    func image(at index: Int, maxPixelSize: Int) -> CGImage? {
        try? reader.render(pageAt: index, maxPixelSize: maxPixelSize)
    }
}
