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

    init(url: URL) throws {
        let reader = try PdfDocumentReader(url: url)
        self.reader = reader
        self.pageCount = reader.pageCount
    }

    /// One page, rasterised at the size it will be drawn.
    ///
    /// `nil` rather than a throw: the reader shows a named "page unavailable"
    /// placeholder for a page it cannot produce, and one bad page in a PDF should
    /// not close the whole document.
    func image(at index: Int, maxPixelSize: Int) -> CGImage? {
        try? reader.render(pageAt: index, maxPixelSize: maxPixelSize)
    }
}
