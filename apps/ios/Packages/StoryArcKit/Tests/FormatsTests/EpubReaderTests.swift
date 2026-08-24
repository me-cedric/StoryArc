import Foundation
import Testing

@testable import Formats

/// Asserted against the shared corpus in `packages/test-fixtures`. Android's
/// `EpubReaderTest` reads the same manifest, so neither platform can privately
/// redefine what a correct parse is.
///
/// Three fixtures cover the four combinations `publication-formats` promises:
/// EPUB 3 reflowable, EPUB 2 reflowable, and EPUB 3 fixed-layout. EPUB 2
/// fixed-layout does not exist — pre-pagination was introduced in EPUB 3.
@Suite("EPUB reading")
struct EpubReaderTests {
    private func reader(_ name: String) async throws -> EpubReader {
        try await EpubReader(source: try FileSource(url: FixtureCorpus.url("ebooks/\(name)")))
    }

    @Test("Metadata matches the manifest", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func metadata(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        let reader = try await reader(name)
        #expect(reader.metadata.title == fixture.expectedTitle, "\(name)")
        #expect(reader.metadata.author == fixture.expectedAuthor, "\(name)")
        #expect(reader.metadata.language == fixture.expectedLanguage, "\(name)")
        #expect(reader.metadata.identifier == fixture.expectedIdentifier, "\(name)")
    }

    @Test("The version is read from the package, not guessed", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func version(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        #expect(try await reader(name).version == fixture.epubVersion, "\(name)")
    }

    @Test("The spine is the reading order, with hrefs resolved", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func spine(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        let reader = try await reader(name)
        #expect(reader.spine.count == fixture.expectedSpineCount, "\(name)")
        // Resolved against the package document's directory, not left relative:
        // `ch1.xhtml` in `OEBPS/package.opf` is `OEBPS/ch1.xhtml` in the container.
        #expect(reader.spine.map(\.href) == fixture.expectedSpineHrefs, "\(name)")
    }

    @Test("Spine items carry their media type")
    func spineMediaTypes() async throws {
        let reader = try await reader("fixture.epub")
        #expect(reader.spine.allSatisfy { $0.mediaType == "application/xhtml+xml" })
    }

    // MARK: - The two conventions per feature

    @Test("The cover is found under either convention", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func cover(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        let reader = try await reader(name)
        // EPUB 3 marks the cover with a manifest property; EPUB 2 names an item id
        // from a metadata meta. Both are pinned, because a version number is not a
        // promise about which convention a file actually used.
        #expect(reader.coverHref == fixture.expectedCoverHref, "\(name)")
        let data = try #require(await reader.coverData())
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "\(name)")
    }

    @Test("The table of contents is read from a nav document or an NCX", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func toc(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        let reader = try await reader(name)
        // The EPUB 3 fixtures have a nav document; the EPUB 2 one has only an NCX,
        // reached through the spine's `toc` attribute rather than by media type.
        #expect(reader.toc.map(\.title) == fixture.expectedTocTitles, "\(name)")
    }

    @Test("Table-of-contents hrefs resolve and drop their fragments")
    func tocHrefs() async throws {
        let reader = try await reader("fixture.epub")
        #expect(reader.toc.map(\.href) == ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])
    }

    // MARK: - Fixed layout

    @Test("A pre-paginated publication says so, and a reflowable one does not", arguments: [
        "fixture.epub", "epub2.epub", "fixed-layout.epub",
    ])
    func fixedLayout(name: String) async throws {
        let fixture = try #require(FixtureCorpus.ebook(name))
        // Getting this wrong means offering typography controls for a comic, which
        // `ebook-reader` forbids.
        #expect(try await reader(name).isFixedLayout == fixture.isFixedLayout, "\(name)")
    }

    // MARK: - Reading content

    @Test("A spine item's bytes come back")
    func spineData() async throws {
        let reader = try await reader("fixture.epub")
        let first = try #require(reader.spine.first)
        let data = try await reader.data(at: first.href)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("Chapter One"))
    }

    // MARK: - Refusals

    @Test("A ZIP that is not an EPUB is refused as such")
    func plainZipIsNotAnEpub() async throws {
        let url = FixtureCorpus.url("comics/natural-sort.cbz")
        await #expect(throws: EpubError.notEpub) {
            _ = try await EpubReader(source: try FileSource(url: url))
        }
    }

    @Test("Bytes that are not even a ZIP are refused")
    func notAZip() async throws {
        await #expect(throws: EpubError.notEpub) {
            _ = try await EpubReader(source: DataSource(Data(repeating: 0x41, count: 1024)))
        }
    }

    @Test("An EPUB with no container document is named, not silently empty")
    func missingContainer() async throws {
        // The right mimetype and nothing else. Returning an empty publication
        // would put a book in the library that cannot be opened.
        let url = FixtureCorpus.url("ebooks/no-package.epub")
        await #expect(throws: EpubError.noPackageDocument) {
            _ = try await EpubReader(source: try FileSource(url: url))
        }
    }
}
