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
}
