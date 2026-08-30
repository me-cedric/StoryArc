import Foundation
import Testing

@testable import Formats

/// A cover for an EPUB that declares none.
///
/// `publication-formats`: "WHEN an EPUB declares a cover image THEN that image is used;
/// otherwise the first page of the spine is rendered as the cover."
///
/// Two halves, tested separately because they fail differently: finding the image a
/// page of XHTML points at is string work with a dozen shapes, and choosing between the
/// declared cover and that one is a rule over a real container. Android's
/// `EpubSpineCoverTest` asserts the same cases in the same order.
@Suite("EPUB spine cover")
struct EpubSpineCoverTests {
    private func reader(_ name: String) async throws -> EpubReader {
        try await EpubReader(source: try FileSource(url: FixtureCorpus.url("ebooks/\(name)")))
    }

    // MARK: - Finding the image on the page

    @Test("An img element's source is found")
    func imgSource() {
        let page = Data("<html><body><img src=\"page1.png\" width=\"2\"/></body></html>".utf8)
        #expect(EpubSpineCover.imageReferences(in: page) == ["page1.png"])
    }

    @Test("An SVG image is found too, however it spells its href")
    func svgImage() {
        let namespaced = Data(
            "<svg><image xlink:href=\"images/plate.jpg\" /></svg>".utf8
        )
        #expect(EpubSpineCover.imageReferences(in: namespaced).contains("images/plate.jpg"))
        let plain = Data("<svg><image href='images/plate.jpg'/></svg>".utf8)
        #expect(plain.isEmpty == false)
        #expect(EpubSpineCover.imageReferences(in: plain).contains("images/plate.jpg"))
    }

    @Test("A CSS background is a picture too, quoted or not")
    func cssBackground() {
        let quoted = Data("<div style=\"background-image: url('bg.png')\"></div>".utf8)
        #expect(EpubSpineCover.imageReferences(in: quoted).contains("bg.png"))
        let bare = Data("<div style=\"background-image: url(bg.png)\"></div>".utf8)
        #expect(EpubSpineCover.imageReferences(in: bare).contains("bg.png"))
    }

    @Test("A page that points at nothing yields nothing")
    func noReferences() {
        let page = Data("<html><body><h1>Title</h1><p>Words.</p></body></html>".utf8)
        #expect(EpubSpineCover.imageReferences(in: page).isEmpty)
    }

    @Test("A stylesheet link is not a cover")
    func stylesheetsAreNotCovers() {
        let page = Data("<head><link rel=\"stylesheet\" href=\"style.css\"/></head>".utf8)
        let references = EpubSpineCover.imageReferences(in: page)
        #expect(references == ["style.css"])
        #expect(EpubSpineCover.looksLikeAnImage("style.css") == false)
    }

    @Test("An href is resolved against the page that declared it, not against the root")
    func resolution() {
        #expect(EpubSpineCover.resolve("page1.png", against: "OEBPS") == "OEBPS/page1.png")
        #expect(
            EpubSpineCover.resolve("../images/p.png", against: "OEBPS/text") == "OEBPS/images/p.png"
        )
        #expect(EpubSpineCover.resolve("/OEBPS/p.png", against: "OEBPS") == "OEBPS/p.png")
        #expect(EpubSpineCover.resolve("p.png#anchor", against: "") == "p.png")
    }

    // MARK: - Choosing the cover

    @Test("A publication that declares a cover keeps it", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func declaredCoverWins(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        let resolved = await (try reader(name)).coverOrSpineHref()
        #expect(resolved == fixture.expectedCoverHref, "\(name)")
        #expect(resolved == fixture.expectedSpineCoverHref, "\(name)")
    }

    @Test("A publication that declares none takes the image its first page shows")
    func spineCoverIsFound() async throws {
        let fixture = try #require(FixtureCorpus.ebook("spine-cover.epub"))
        let reader = try await reader("spine-cover.epub")

        // Nothing is declared: this is the case the library used to draw a placeholder for.
        #expect(reader.coverHref == nil)
        #expect(fixture.expectedSpineCoverHref == "OEBPS/page1.png")
        #expect(await reader.coverOrSpineHref() == fixture.expectedSpineCoverHref)
    }

    @Test("The cover found this way is a real entry, so its bytes read like any other")
    func spineCoverIsReadable() async throws {
        let reader = try await reader("spine-cover.epub")
        let href = try #require(await reader.coverOrSpineHref())
        let data = try await reader.data(at: href)
        #expect(!data.isEmpty)
        #expect(PageCodec.of(data) == .png)
    }

    @Test("A first page of text alone leaves the publication without a cover")
    func textOnlyFirstPageHasNoCover() async throws {
        let fixture = try #require(FixtureCorpus.ebook("series.epub"))
        #expect(fixture.expectedSpineCoverHref == nil)
        let resolved = await (try reader("series.epub")).coverOrSpineHref()
        #expect(resolved == nil)
    }
}
