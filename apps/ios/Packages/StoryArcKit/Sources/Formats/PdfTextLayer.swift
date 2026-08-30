public import CoreGraphics
internal import Foundation

internal import PDFKit

/// A run of words in a PDF, and where they sit on the page.
///
/// The rectangles are in **normalised page space**: `0...1` across and down, origin at the
/// page's top-left corner. Not points, and deliberately so — the reader draws the mark over a
/// page it has rasterised at whatever size the screen asked for, and normalised rectangles are
/// the only ones that survive that without the drawing code knowing about PDF points, page
/// boxes or the two platforms' opposite ideas of which way up a page is.
///
/// Android's `PdfTextSelection` reports the same shape in the same space.
public struct PdfTextSelection: Sendable, Equatable {
    public let locator: PdfLocator
    /// The words themselves, as the reader will copy or quote them.
    public let text: String
    /// One rectangle per line of the run, so a selection across a line break draws as two
    /// bars rather than as one block over the paragraph between them.
    public let rects: [CGRect]

    public init(locator: PdfLocator, text: String, rects: [CGRect]) {
        self.locator = locator
        self.text = text
        self.rects = rects
    }
}

// The text layer, as the reader uses it: selecting words on a page, finding the same words
// again, and searching the whole document.
//
// Split from `PdfDocumentReader` because that type is the document — count, size, raster —
// and this is what a *reader* does with the text on it. `ebook-reader` asks for both, and
// keeping them apart is what stopped one file being the whole of PDF.
public extension PdfDocumentReader {

    /// How close two normalised points have to be before a drag counts as a tap.
    ///
    /// A long press with no drag means "the word under my finger", which is a different
    /// PDFKit call from "everything between these two points" — the latter returns nothing
    /// at all when the two points are the same.
    static var wordThreshold: CGFloat { 0.005 }

    /// What lies between two points on a page, in normalised page space.
    ///
    /// `nil` when the drag crossed no text: the reader then shows nothing rather than an
    /// empty menu, which is the honest answer to selecting a margin.
    func selection(onPage index: Int, from: CGPoint, to: CGPoint) -> PdfTextSelection? {
        guard let page = try? page(at: index) else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }

        let start = point(from, in: box)
        let end = point(to, in: box)
        let isTap = abs(from.x - to.x) < Self.wordThreshold
            && abs(from.y - to.y) < Self.wordThreshold

        let selected = isTap
            ? page.selectionForWord(at: start)
            : page.selection(from: start, to: end)
        guard let selected else { return nil }
        return described(selected, on: page, at: index, in: box)
    }

    /// The same words again, from a stored locator.
    ///
    /// What paints a highlight back onto a page the reader has turned away from and come
    /// back to. `nil` when the locator names nothing on that page any more.
    func selection(for locator: PdfLocator) -> PdfTextSelection? {
        guard locator.end > locator.start, let page = try? page(at: locator.page) else {
            return nil
        }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let range = NSRange(location: locator.start, length: locator.end - locator.start)
        guard let selected = page.selection(for: range) else { return nil }
        return described(selected, on: page, at: locator.page, in: box)
    }

    /// A normalised point in the page's own coordinates. PDF counts up from the bottom.
    private func point(_ normalised: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(
            x: box.minX + normalised.x * box.width,
            y: box.maxY - normalised.y * box.height
        )
    }

    /// A page rectangle back in normalised space, counting down from the top.
    private func normalised(_ rect: CGRect, in box: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - box.minX) / box.width,
            y: (box.maxY - rect.maxY) / box.height,
            width: rect.width / box.width,
            height: rect.height / box.height
        )
    }

    private func described(
        _ selected: PDFSelection,
        on page: PDFPage,
        at index: Int,
        in box: CGRect
    ) -> PdfTextSelection? {
        let ranges = (0..<selected.numberOfTextRanges(on: page)).map {
            selected.range(at: $0, on: page)
        }
        guard let start = ranges.map(\.location).min(),
              let end = ranges.map({ $0.location + $0.length }).max(),
              end > start
        else { return nil }

        let text = (selected.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return PdfTextSelection(
            locator: PdfLocator(page: index, start: start, end: end),
            text: text,
            // Per line, because one rectangle around a selection that wraps would cover the
            // whole paragraph between its first word and its last.
            rects: selected.selectionsByLine()
                .map { normalised($0.bounds(for: page), in: box) }
                .filter { $0.width > 0 && $0.height > 0 }
        )
    }
}
