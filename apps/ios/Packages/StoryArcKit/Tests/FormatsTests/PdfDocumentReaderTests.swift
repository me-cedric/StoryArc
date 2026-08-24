import CoreGraphics
import Foundation
import Testing

@testable import Formats

/// Asserted against the shared corpus in `packages/test-fixtures`.
///
/// Android's `PdfDocumentReaderTest` asserts the page-level half of this — count,
/// size, rendering — and deliberately not the text half. `ebook-reader` makes
/// text-layer features iOS-only in 1.0, so the asymmetry is the specified
/// behaviour rather than missing coverage.
@Suite("PDF reading")
struct PdfDocumentReaderTests {
    private func reader(_ name: String) throws -> PdfDocumentReader {
        try PdfDocumentReader(url: FixtureCorpus.url("comics/\(name)"))
    }

    @Test("Page count matches the manifest", arguments: ["text-pages.pdf", "image-pages.pdf"])
    func pageCount(name: String) throws {
        let fixture = try #require(FixtureCorpus.pdf(name))
        #expect(try reader(name).pageCount == fixture.expectedPageCount)
    }

    @Test("Page size is reported in points, so both platforms agree on fit", arguments: [
        "text-pages.pdf", "image-pages.pdf",
    ])
    func pageSizeInPoints(name: String) throws {
        let fixture = try #require(FixtureCorpus.pdf(name))
        let expected = try #require(fixture.expectedPageSizePoints)
        let size = try reader(name).sizePoints(at: 0)
        #expect(Int(size.width) == expected[0])
        #expect(Int(size.height) == expected[1])
    }

    @Test("An image-only PDF keeps the corpus page aspect")
    func imagePdfAspect() throws {
        let fixture = try #require(FixtureCorpus.pdf("image-pages.pdf"))
        let aspect = try #require(fixture.expectedAspect)
        let size = try reader("image-pages.pdf").sizePoints(at: 0)
        // 2:3 portrait, the same ratio every fixture page uses, so the
        // cross-platform fit assertion has an exact number rather than a
        // tolerance.
        #expect(size.width / size.height == CGFloat(aspect[0]) / CGFloat(aspect[1]))
    }

    // MARK: - Rendering

    @Test("A page renders bounded on its longest edge, and never upscales")
    func renderIsBounded() throws {
        let reader = try reader("image-pages.pdf")
        let full = try reader.render(pageAt: 0)
        #expect(full.width == 200 && full.height == 300)

        let bounded = try reader.render(pageAt: 0, maxPixelSize: 150)
        #expect(max(bounded.width, bounded.height) == 150)
        #expect(bounded.width == 100 && bounded.height == 150)

        // Asking for more than the page has must not inflate it, matching
        // PageDecoder's contract for image pages.
        let oversized = try reader.render(pageAt: 0, maxPixelSize: 4000)
        #expect(oversized.width == 200 && oversized.height == 300)
    }

    @Test("A rendered image page carries the pixels the fixture drew")
    func renderedPixelsAreRight() throws {
        let image = try reader("image-pages.pdf").render(pageAt: 0)
        // The fixture fills page 1 with hue(1) = (37, 91, 151). Sampling proves
        // the page really rasterised, rather than returning a blank context of
        // the right size.
        let centre = try #require(samplePixel(image, atX: image.width / 2, y: image.height / 2))
        #expect(centre.red == 37)
        #expect(centre.green == 91)
        #expect(centre.blue == 151)
    }

    @Test("A page index outside the document is refused, not clamped")
    func pageOutOfRange() throws {
        let reader = try reader("image-pages.pdf")
        #expect(throws: PdfError.pageOutOfRange(3)) { try reader.sizePoints(at: 3) }
        #expect(throws: PdfError.pageOutOfRange(-1)) { try reader.render(pageAt: -1) }
    }

    @Test("Bytes that are not a PDF are refused")
    func notAPdf() throws {
        #expect(throws: PdfError.unreadable) {
            _ = try PdfDocumentReader(data: Data(repeating: 0x41, count: 1024))
        }
    }

    // MARK: - Text layer

    @Test("A text layer is detected rather than assumed from the extension")
    func textLayerDetected() throws {
        #expect(try reader("text-pages.pdf").hasTextLayer)
        // The scanned-comic case. `ebook-reader` forbids offering selection or
        // search when there is no text to find, on either platform.
        #expect(try reader("image-pages.pdf").hasTextLayer == false)
    }

    @Test("Each page's text matches the manifest")
    func pageText() throws {
        let fixture = try #require(FixtureCorpus.pdf("text-pages.pdf"))
        let expected = try #require(fixture.expectedPageText)
        let reader = try reader("text-pages.pdf")
        for (index, text) in expected.enumerated() {
            #expect(try reader.text(at: index) == text)
        }
    }

    @Test("An image-only PDF yields no text on any page")
    func imagePdfHasNoText() throws {
        let reader = try reader("image-pages.pdf")
        for index in 0..<reader.pageCount {
            #expect(try reader.text(at: index) == nil)
        }
    }

    @Test("In-publication search returns the pages a phrase appears on")
    func search() throws {
        let reader = try reader("text-pages.pdf")
        #expect(reader.search("Chapter Two") == [1])
        // Case-insensitive, because a reader's search box is not a grep.
        #expect(reader.search("chapter three") == [2])
        // Present on every page, so every page comes back, in order.
        #expect(reader.search("Chapter") == [0, 1, 2])
        #expect(reader.search("nowhere in this document").isEmpty)
        #expect(reader.search("").isEmpty)
    }

    @Test("The outline is read with its titles and destinations")
    func outline() throws {
        let fixture = try #require(FixtureCorpus.pdf("text-pages.pdf"))
        let expected = try #require(fixture.expectedOutlineTitles)
        let outline = try reader("text-pages.pdf").outline
        #expect(outline.map(\.title) == expected)
        #expect(outline.map(\.pageIndex) == [0, 1, 2])
    }

    @Test("A PDF with no outline reports an empty one rather than failing")
    func noOutline() throws {
        #expect(try reader("image-pages.pdf").outline.isEmpty)
    }

    /// One pixel out of a rendered page, so a test can prove the raster happened.
    private func samplePixel(
        _ image: CGImage, atX x: Int, y: Int
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        guard offset + 2 < buffer.count else { return nil }
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2])
    }
}
