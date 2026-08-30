public import CoreGraphics
public import Foundation

internal import PDFKit

/// One entry in a PDF's document outline.
public struct PdfOutlineItem: Sendable, Equatable {
    public let title: String
    /// The page the entry jumps to, or `nil` when the destination is unresolvable.
    public let pageIndex: Int?
    public let children: [PdfOutlineItem]
}

public enum PdfError: Error, Equatable {
    /// PDFKit refused the file. Encrypted, truncated, or not a PDF.
    case unreadable
    case pageOutOfRange(Int)
}

/// Reads a PDF as a paged publication.
///
/// The page: count, size in points, and rendering on demand. `ebook-reader`
/// requires a several-hundred-megabyte PDF opened from a remote source to render
/// pages as they are needed, which is why nothing here rasterises up front.
///
/// What is written on the page is next door, in `PdfTextLayer`. The split is not
/// tidiness: on Android the text half is a separate reader that a device may not
/// have at all (ADR-0011), and keeping the same seam here is what makes the two
/// codebases answer the same question in the same place.
///
/// The document outline stays here, and stays iOS-only. PDFKit reads it;
/// Android's PDF API exposes links and text but no outline, so `ebook-reader`'s
/// "the document outline works" is honoured on one platform and the control is
/// absent rather than empty on the other. ADR-0011 records that.
///
/// Deliberately **not** `Sendable`. `PDFDocument` is a mutable reference type
/// with no thread-safety guarantee, and claiming otherwise would be a lie the
/// compiler cannot catch. A caller that needs one across concurrency domains
/// should own it from a single actor, the way the reader UI does.
public struct PdfDocumentReader {
    public let pageCount: Int
    /// Whether any of the pages this probes carries extractable text.
    ///
    /// Drives whether the reader offers selection and search at all. A scanned
    /// comic has no text layer, and `ebook-reader` forbids offering a capability
    /// that is absent — so this is checked rather than assumed from the extension.
    ///
    /// Bounded by ``textProbePages`` rather than reading the whole document: a
    /// publication whose first two dozen pages carry not one word is a scan, and
    /// Android — where opening a page is the expensive part — probes the same
    /// number for the same reason.
    public let hasTextLayer: Bool

    /// How many pages ``hasTextLayer`` reads before it concludes there is no text.
    public static let textProbePages = 24

    private let document: PDFDocument

    public init(url: URL) throws {
        guard let document = PDFDocument(url: url) else { throw PdfError.unreadable }
        self.init(document: document)
    }

    public init(data: Data) throws {
        guard let document = PDFDocument(data: data) else { throw PdfError.unreadable }
        self.init(document: document)
    }

    private init(document: PDFDocument) {
        self.document = document
        self.pageCount = document.pageCount
        // Stops at the first page with text. A scan pays for the whole probe, but
        // only once, and only for the two dozen pages the bound allows.
        let probed = min(document.pageCount, PdfDocumentReader.textProbePages)
        self.hasTextLayer = (0..<probed).contains { index in
            guard let text = document.page(at: index)?.string else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// A page's size in PDF points, which is what fit and zoom are computed from.
    ///
    /// Points rather than pixels on purpose: the same page must present at the
    /// same aspect ratio and fit on both platforms, and pixels depend on the
    /// screen while points do not.
    public func sizePoints(at index: Int) throws -> CGSize {
        try page(at: index).bounds(for: .mediaBox).size
    }

    /// Renders one page, bounded on its longest edge.
    ///
    /// The bound is the same contract `PageDecoder.decode` offers for images, so
    /// a PDF page and a comic page cost the same to show. Never upscales: asking
    /// for more than the page has returns it at its natural size.
    public func render(pageAt index: Int, maxPixelSize: Int? = nil) throws -> CGImage {
        let page = try self.page(at: index)
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { throw PdfError.unreadable }

        let scale: CGFloat
        if let maxPixelSize, maxPixelSize > 0 {
            scale = min(CGFloat(maxPixelSize) / max(box.width, box.height), 1)
        } else {
            scale = 1
        }
        let width = max(Int((box.width * scale).rounded()), 1)
        let height = max(Int((box.height * scale).rounded()), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw PdfError.unreadable }

        // A PDF page has no background of its own, so an unpainted context would
        // render dark text onto transparency and read as black on black.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else { throw PdfError.unreadable }
        return image
    }

    // MARK: - Text layer

    /// A page's text, or `nil` when the page has none.
    public func text(at index: Int) throws -> String? {
        let raw = try page(at: index).string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty ?? true) ? nil : raw
    }

    /// The document outline, empty when the PDF carries none.
    public var outline: [PdfOutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        return children(of: root)
    }

    private func children(of node: PDFOutline) -> [PdfOutlineItem] {
        (0..<node.numberOfChildren).compactMap { position in
            guard let child = node.child(at: position) else { return nil }
            let index = child.destination?.page.map { document.index(for: $0) }
            return PdfOutlineItem(
                title: child.label ?? "",
                pageIndex: index == NSNotFound ? nil : index,
                children: children(of: child)
            )
        }
    }

    /// Internal rather than private: the text layer is an extension in another file, and a
    /// `private` member cannot be reached from one.
    func page(at index: Int) throws -> PDFPage {
        guard index >= 0, index < document.pageCount, let page = document.page(at: index) else {
            throw PdfError.pageOutOfRange(index)
        }
        return page
    }
}
