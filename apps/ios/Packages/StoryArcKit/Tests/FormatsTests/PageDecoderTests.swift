import CoreGraphics
import Foundation
import Testing

@testable import Formats

/// Closes the last *Assumed* row for iOS image decoding in ADR-0005: not "the
/// API exists" but "a page from the corpus decodes to a bitmap of the expected
/// size, and downsampling actually downsamples".
@Suite("Page decoding")
struct PageDecoderTests {
    private func page(from archive: String) async throws -> Data {
        let opened = try await ComicArchiveOpener.open(fileAt: FixtureCorpus.url("comics/\(archive)"))
        let first = try #require(opened.pages.first)
        return try await opened.data(for: first)
    }

    @Test("Dimensions come from the header without decoding the pixels")
    func dimensionsFromHeader() async throws {
        let data = try await page(from: "large-page.cbz")

        let size = try PageDecoder.dimensions(of: data)

        #expect(size == CGSize(width: 2000, height: 3000))
    }

    @Test("A full decode produces the page at its real size")
    func fullDecode() async throws {
        let data = try await page(from: "large-page.cbz")

        let image = try PageDecoder.decode(data)

        #expect(image.width == 2000)
        #expect(image.height == 3000)
    }

    @Test("Downsampling bounds the longest edge and keeps the aspect ratio")
    func downsample() async throws {
        let data = try await page(from: "large-page.cbz")

        let image = try PageDecoder.decode(data, maxPixelSize: 600)

        // 2000×3000 constrained to 600 on the long edge → 400×600.
        #expect(max(image.width, image.height) <= 600)
        #expect(image.height == 600)
        #expect(image.width == 400)
    }

    @Test("Asking for more than the source has does not upscale")
    func noUpscale() async throws {
        let data = try await page(from: "large-page.cbz")

        let image = try PageDecoder.decode(data, maxPixelSize: 9000)

        #expect(image.width <= 2000)
        #expect(image.height <= 3000)
    }

    @Test("A tiny page still decodes, so the small fixtures stay usable")
    func tinyPage() async throws {
        let data = try await page(from: "natural-sort.cbz")

        let size = try PageDecoder.dimensions(of: data)
        let image = try PageDecoder.decode(data)

        #expect(size == CGSize(width: 2, height: 3))
        #expect(image.width == 2)
    }

    @Test("Bytes that are not an image are reported, not crashed on")
    func notAnImage() {
        let junk = Data("this is not a picture".utf8)

        #expect(throws: PageDecoder.DecodeError.unrecognised) {
            _ = try PageDecoder.dimensions(of: junk)
        }
    }

    @Test("A double-page spread is detected from its aspect ratio")
    func spreadDetection() async throws {
        let opened = try await ComicArchiveOpener.open(
            fileAt: FixtureCorpus.url("comics/double-page-spread.cbz")
        )
        // The manifest records index 1 as the spread; the other two are portrait.
        var verdicts: [Bool] = []
        for page in opened.pages {
            let size = try PageDecoder.dimensions(of: try await opened.data(for: page))
            verdicts.append(PageDecoder.isSpread(size))
        }

        #expect(verdicts == [false, true, false])
    }

    @Test("A merely-slightly-wide page is not a spread")
    func spreadThreshold() {
        #expect(!PageDecoder.isSpread(CGSize(width: 110, height: 100)))
        #expect(PageDecoder.isSpread(CGSize(width: 200, height: 100)))
        #expect(!PageDecoder.isSpread(CGSize(width: 100, height: 0)))
    }
}
