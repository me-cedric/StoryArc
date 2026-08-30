import Foundation
import StoryArcCore
import Testing

@testable import Formats

/// The seam between the format layer and the library, so these assert on what a
/// library row would show rather than on what a parser found.
@Suite("Publication indexing")
struct PublicationIndexerTests {
    private func index(_ relativePath: String) async throws -> Publication {
        try await PublicationIndexer.index(fileAt: FixtureCorpus.url(relativePath))
    }

    @Test("Every supported container indexes to its own format", arguments: [
        ("comics/natural-sort.cbz", PublicationFormat.cbz),
        ("comics/tar-store.cbt", PublicationFormat.cbt),
        ("comics/rar5-store.cbr", PublicationFormat.cbr),
        ("comics/text-pages.pdf", PublicationFormat.pdf),
        ("ebooks/fixture.epub", PublicationFormat.epub),
    ])
    func formats(path: String, expected: PublicationFormat) async throws {
        #expect(try await index(path).format == expected, "\(path)")
    }

    @Test("Format comes from content, so a ZIP named .cbr indexes as a CBZ")
    func formatFromContent() async throws {
        // The same rule the archive layer follows, carried up to the library so a
        // filter by format does not lie about a mis-named file.
        #expect(try await index("comics/mislabelled-zip.cbr").format == .cbz)
    }

    @Test("An EPUB is told apart from a plain ZIP by its contents")
    func epubIsNotACbz() async throws {
        // Both are ZIPs. Only the mimetype entry and the container document say
        // which, and guessing from the extension would put every EPUB in the comics
        // shelf.
        #expect(try await index("ebooks/fixture.epub").format == .epub)
        #expect(try await index("comics/natural-sort.cbz").format == .cbz)
    }

    // MARK: - Metadata precedence

    @Test("Embedded metadata beats the filename")
    func embeddedWins() async throws {
        let publication = try await index("comics/manga-metadata.cbz")
        #expect(publication.series == "Fixture Manga")
        #expect(publication.number == "3")
        #expect(publication.volume == 2)
        #expect(publication.year == 2026)
        #expect(publication.publisher == "Fixture Press")
        #expect(publication.authors == ["First Writer", "Second Writer"])
        #expect(publication.origin == .embedded)
    }

    @Test("A file with no embedded metadata falls back to its filename, and says so")
    func inferredFallback() async throws {
        let publication = try await index("comics/natural-sort.cbz")
        #expect(publication.origin == .inferred)
        // The flag is the point: an authoritative source may replace this without
        // asking the user to resolve a conflict the app invented.
        #expect(publication.origin.yields(to: .authoritative))
        #expect(publication.origin.yields(to: .embedded))
    }

    @Test("Embedded metadata does not yield to a filename guess")
    func embeddedDoesNotYield() async throws {
        let publication = try await index("comics/manga-metadata.cbz")
        #expect(!publication.origin.yields(to: .inferred))
    }

    @Test("Reading direction reaches the library, not just the parser")
    func readingDirection() async throws {
        #expect(try await index("comics/manga-metadata.cbz").readingDirection == .rightToLeft)
        #expect(try await index("comics/japanese-no-direction.cbz").readingDirection == .rightToLeft)
        #expect(try await index("comics/natural-sort.cbz").readingDirection == .leftToRight)
    }

    @Test("A designated cover reaches the library")
    func cover() async throws {
        #expect(try await index("comics/manga-metadata.cbz").coverPath == "p2.png")
        #expect(try await index("comics/natural-sort.cbz").coverPath == "page1.png")
    }

    // MARK: - What a row shows

    @Test("A title is used when the file states one")
    func statedTitle() async throws {
        #expect(try await index("comics/manga-metadata.cbz").displayTitle == "The Third Chapter")
    }

    @Test("Without a title, series and number are assembled")
    func assembledTitle() async throws {
        #expect(try await index("comics/japanese-no-direction.cbz").displayTitle == "Undeclared Direction")
    }

    @Test("Without either, the filename is shown rather than nothing")
    func filenameTitle() async throws {
        // A library row with no text at all is worse than one showing a filename.
        let publication = try await index("comics/natural-sort.cbz")
        #expect(!publication.displayTitle.isEmpty)
    }

    @Test("An EPUB's title comes from its package document")
    func epubTitle() async throws {
        let publication = try await index("ebooks/fixture.epub")
        #expect(publication.displayTitle == "Fixture Publication")
        #expect(publication.authors == ["StoryArc Fixtures"])
        #expect(publication.language == "en")
        #expect(publication.origin == .embedded)
    }

    @Test("A fixed-layout EPUB is marked as one")
    func fixedLayout() async throws {
        // Drives which reader opens it, so a comic-as-EPUB is not offered font
        // controls it cannot honour.
        #expect(try await index("ebooks/fixed-layout.epub").isFixedLayout)
        #expect(try await index("ebooks/fixture.epub").isFixedLayout == false)
    }

    // MARK: - Counts and capability

    @Test("Page count and skipped count are both recorded")
    func counts() async throws {
        let intact = try await index("comics/natural-sort.cbz")
        #expect(intact.pageCount == 12)
        #expect(intact.skippedPageCount == 0)
        #expect(!intact.isPartial)

        let damaged = try await index("comics/truncated.cbz")
        #expect((damaged.pageCount ?? 0) > 0)
        #expect((damaged.pageCount ?? 99) < 12)
    }

    @Test("An EPUB records its spine length, not a page count")
    func epubSpineCount() async throws {
        // An EPUB's pages depend on the type size the reader is set to, so there is
        // no page count to record.
        #expect(try await index("ebooks/fixture.epub").pageCount == 2)
    }

    @Test("Streaming capability is recorded per publication", arguments: [
        ("comics/natural-sort.cbz", StreamingCapability.streams),
        ("comics/rar5-store.cbr", StreamingCapability.streams),
        ("comics/rar5-solid.cbr", StreamingCapability.downloadOnly),
        ("comics/rar4-solid.cbr", StreamingCapability.refused),
    ])
    func streaming(path: String, expected: StreamingCapability) async throws {
        #expect(try await index(path).streaming == expected, "\(path)")
    }

    @Test("A solid RAR4 is listed and marked unopenable, not dropped")
    func refusedIsStillListed() async throws {
        // The library should show it and say why. Dropping it silently leaves the
        // user hunting for a comic they can see in the folder.
        let publication = try await index("comics/rar4-solid.cbr")
        #expect(!publication.isOpenable)
        #expect(!publication.displayTitle.isEmpty)
    }

    // MARK: - Refusals

    @Test("A 7-Zip comic is refused by name")
    func sevenZipNamed() async throws {
        await #expect(throws: PublicationIndexer.IndexError.unsupported(format: "CB7")) {
            _ = try await index("comics/refused.cb7")
        }
    }

    @Test("A file that is not there is named as missing, not as unsupported")
    func missingFile() async throws {
        await #expect(throws: PublicationIndexer.IndexError.unreadable(reason: "the file is not there")) {
            _ = try await PublicationIndexer.index(
                fileAt: URL(fileURLWithPath: "/nowhere/at/all.cbz")
            )
        }
    }

    @Test("A verification failure is its own type, so a caller has to name it")
    func verificationFailureIsItsOwnType() async {
        // `offline-downloads` verifies a finished download by indexing it, and the queue
        // that does the verifying has to catch what this throws. Android's caught only
        // I/O failures, and an index failure is not one -- so a truncated archive threw
        // out of the coroutine and took the app down instead of marking the download
        // failed. Pinned on both platforms because reparenting this type re-opens that.
        var thrown: (any Error)?
        do {
            _ = try await index("comics/refused.cb7")
        } catch {
            thrown = error
        }
        #expect(thrown is PublicationIndexer.IndexError)
        #expect(!(thrown is URLError))
        #expect(!(thrown is CocoaError))
    }

    // MARK: - Identity

    @Test("Identity is path-keyed during a scan, and matches itself")
    func identity() async throws {
        let publication = try await index("comics/natural-sort.cbz")
        #expect(publication.identity.normalizedPath != nil)
        #expect(!publication.identity.isEmpty)
        #expect(publication.id.hasPrefix("path:"))
    }

    @Test("A content digest is stable, and differs between publications")
    func contentDigest() async throws {
        let first = try await PublicationIndexer.contentDigest(
            fileAt: FixtureCorpus.url("comics/natural-sort.cbz")
        )
        let again = try await PublicationIndexer.contentDigest(
            fileAt: FixtureCorpus.url("comics/natural-sort.cbz")
        )
        let other = try await PublicationIndexer.contentDigest(
            fileAt: FixtureCorpus.url("comics/nested-chapters.cbz")
        )
        #expect(first == again)
        #expect(first != other)
        #expect(first.count == 64)
    }
}
