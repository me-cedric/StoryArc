import Foundation
import Testing

import StoryArcCore
@testable import ReaderFeature

/// The reader's own loop: open, list pages, decode a window, move.
///
/// Runs on the host because everything it needs — ZIP, PDFKit, ImageIO — is
/// available on macOS. Android's equivalent is instrumented, because `Bitmap` and
/// `PdfRenderer` are framework stubs off-device.
@MainActor
@Suite("Reader model")
struct ReaderModelTests {

    /// Walks up from this file to the shared corpus, the same way `FixtureCorpus`
    /// does for the format tests. Both platforms read these files (ADR-0001).
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func url(_ relativePath: String) -> URL {
        Self.corpus.appending(path: relativePath)
    }

    private func publication(_ format: PublicationFormat, at url: URL) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: url.path),
            format: format,
            displayTitle: url.lastPathComponent,
            origin: .inferred
        )
    }

    @Test("A comic archive opens and decodes its first page")
    func opensAnArchive() async {
        let location = url("comics/natural-sort.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure == nil)
        #expect(model.pages.count == 12)
        #expect(model.image(at: 0) != nil)
        // `comic-reader` asks for three pages ahead, so the fourth is not warm yet.
        #expect(model.image(at: 3) != nil)
        #expect(model.image(at: 4) == nil)
    }

    @Test("A PDF pages like an archive, one page at a time")
    func opensAPDF() async {
        let location = url("comics/text-pages.pdf")
        let model = ReaderModel(publication: publication(.pdf, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure == nil)
        // `ebook-reader` requires pages rendered as they are needed. This document
        // is three pages and the window reaches three ahead, so all of it is warm —
        // which is the point: nothing was rasterised *because the file is open*,
        // only because the window covers it.
        #expect(model.pages.count == 3)
        #expect(model.image(at: 0) != nil)
        #expect(model.image(at: 2) != nil)
    }

    @Test("Moving decodes the destination and drops what scrolled away")
    func windowFollowsThePage() async {
        let location = url("comics/natural-sort.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)
        await model.open(maxPixelSize: 256)

        await model.go(to: 6)

        #expect(model.currentIndex == 6)
        #expect(model.image(at: 6) != nil)
        // Three ahead and one behind, per `comic-reader`.
        #expect(model.image(at: 5) != nil)
        #expect(model.image(at: 9) != nil)
        // Beyond the window in either direction, nothing is held — which is what
        // bounds memory.
        #expect(model.image(at: 4) == nil)
        #expect(model.image(at: 10) == nil)
    }

    @Test("Memory pressure narrows the window and gives back what no longer fits")
    func pressureShrinksThePrefetch() async {
        let location = url("comics/natural-sort.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)
        await model.open(maxPixelSize: 256)
        await model.go(to: 6)
        #expect(model.image(at: 9) != nil)

        // `comic-reader`: "prefetch depth shrinks under memory pressure rather than the
        // app being terminated". Straight away, not at the next turn — the pages already
        // held are the ones the system is asking for back.
        await model.noteMemoryPressure(.warning)

        #expect(model.image(at: 6) != nil)
        #expect(model.image(at: 7) != nil)
        #expect(model.image(at: 8) == nil)
        #expect(model.image(at: 9) == nil)

        // Critical leaves only the page on screen.
        await model.noteMemoryPressure(.critical)
        #expect(model.image(at: 6) != nil)
        #expect(model.image(at: 7) == nil)

        // And the pressure lifting puts the window back where the spec asks for it.
        await model.noteMemoryPressure(.normal)
        #expect(model.image(at: 9) != nil)
        #expect(model.image(at: 5) != nil)
    }

    @Test("A ComicInfo double page is known as a spread before it has been decoded")
    func declaredSpreads() async {
        let location = url("comics/manga-metadata.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)

        await model.open(maxPixelSize: 256)

        // The fixture declares `<Page Image="2" DoublePage="true">`, and `comic-reader`
        // shows such a page alone rather than pairing it. Believed over the aspect ratio:
        // the fixture's pages are all the same shape, so nothing here was measured.
        #expect(model.wideIndices.contains(2))
    }

    @Test("A publication that cannot be opened says so rather than showing nothing")
    func reportsFailure() async {
        let location = url("comics/refused.cb7")
        let model = ReaderModel(publication: publication(.cb7, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure != nil)
        #expect(model.pages.isEmpty)
    }

    @Test("The reader carries the count of what the archive could not read")
    func skippedPagesReachTheReader() async {
        // `publication-formats`: a damaged archive opens "whatever pages it can read and
        // states how many were skipped". The count reached the archive and stopped
        // there; the reader is where a person can be told.
        let location = url("comics/unsupported-codec.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.skippedPageCount == 1)
        #expect(model.pages.count == 2)
    }

    @Test("A page in a codec nothing decodes is named, and does not break pagination")
    func undecodablePageIsNamed() async {
        let location = url("comics/unsupported-codec.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)

        await model.open(maxPixelSize: 256)

        // The page before it still draws: the refusal is about one page, not the file.
        #expect(model.image(at: 0) != nil)
        // And the page itself is met by a placeholder that says what it is, rather than
        // by a spinner that never stops — which is what a refusal treated as an unread
        // page produced.
        #expect(model.image(at: 1) == nil)
        #expect(model.isUnavailable(at: 1))
        #expect(model.codecName(at: 1) == "JPEG XL")
    }

    @Test("A page that decoded is not named as a refusal")
    func decodedPagesCarryNoCodec() async {
        let location = url("comics/natural-sort.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.codecName(at: 0) == nil)
        #expect(!model.isUnavailable(at: 0))
    }

    // `publication-formats`: a page too large for the device is "downsampled to the
    // display's needs for viewing and re-decoded at higher resolution when the user
    // zooms". Android's equivalent is instrumented, because `Bitmap` is a framework stub
    // off-device; what both platforms share and both assert is `PrefetchWindow`.

    @Test("Holding a zoom re-decodes the page larger, and letting go gives it back")
    func zoomRedecodesThePage() async throws {
        // A 2000x3000 page, decoded at a fraction of it — which is the case the
        // requirement is about.
        let location = url("comics/large-page.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)
        await model.open(maxPixelSize: 256)

        let fitted = try #require(model.displayImage(at: 0)).width

        await model.holdZoom(3, at: 0)

        #expect((model.displayImage(at: 0)?.width ?? 0) > fitted)
        // The display copy is still there, untouched, which is what makes letting go free.
        #expect(model.image(at: 0)?.width == fitted)

        model.releaseZoom()
        #expect(model.displayImage(at: 0)?.width == fitted)
    }

    @Test("A pinch too small to see does not decode the page again")
    func smallPinchesChangeNothing() async {
        let location = url("comics/large-page.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)
        await model.open(maxPixelSize: 256)
        let fitted = model.displayImage(at: 0)?.width

        await model.holdZoom(1.1, at: 0)

        #expect(model.displayImage(at: 0)?.width == fitted)
    }

    @Test("Memory pressure gives the zoomed copy back before anything else")
    func pressureDropsTheZoom() async {
        let location = url("comics/large-page.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)
        await model.open(maxPixelSize: 256)
        let fitted = model.displayImage(at: 0)?.width
        await model.holdZoom(3, at: 0)
        #expect(model.displayImage(at: 0)?.width != fitted)

        await model.noteMemoryPressure(.critical)

        #expect(model.displayImage(at: 0)?.width == fitted)
        // And under critical pressure a new pinch does not buy one back.
        await model.holdZoom(3, at: 0)
        #expect(model.displayImage(at: 0)?.width == fitted)
    }

    @Test("Turning away from a zoomed page drops the copy it was holding")
    func turningDropsTheZoom() async {
        // Asserted on the held copy rather than on its pixel width: this fixture's pages
        // are tiny, so a re-decode at any bound comes back the same size. What is being
        // checked is that the second copy is let go of, not how large it was.
        let location = url("comics/natural-sort.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)
        await model.open(maxPixelSize: 64)
        await model.holdZoom(4, at: 0)
        #expect(model.zoomed?.index == 0)

        // Far enough that page 0 leaves the window entirely.
        await model.go(to: 8)

        #expect(model.zoomed == nil)
        #expect(model.displayImage(at: 0) == nil)
    }
}
