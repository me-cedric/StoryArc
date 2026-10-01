import CoreGraphics
import Foundation
import StoryArcCore
import Testing

@testable import Formats

/// Covers are loaded separately from indexing, so these assert the split as much
/// as the images: a scan records where a cover is, and this reads it only when a
/// row is about to be seen.
@Suite("Cover loading")
struct CoverLoaderTests {
    private func publication(_ path: String) async throws -> (Publication, URL) {
        let url = FixtureCorpus.url(path)
        return (try await PublicationIndexer.index(fileAt: url), url)
    }

    @Test("A cover comes out of every container that stores one", arguments: [
        "comics/natural-sort.cbz",
        "comics/tar-store.cbt",
        "comics/rar5-store.cbr",
        "ebooks/fixture.epub",
    ])
    func loadsCovers(path: String) async throws {
        let (publication, url) = try await publication(path)
        let image = try await CoverLoader.anyCover(for: publication, at: url, maxPixelSize: 200)
        #expect(image.width > 0 && image.height > 0, "\(path)")
    }

    @Test("A PDF cover is rendered, because its pages are not stored as images")
    func rendersPdfCover() async throws {
        let (publication, url) = try await publication("comics/image-pages.pdf")
        #expect(publication.coverPath == nil)
        let image = try await CoverLoader.anyCover(for: publication, at: url, maxPixelSize: 150)
        // The page box is 200x300, so a 150-pixel bound gives 100x150.
        #expect(image.width == 100)
        #expect(image.height == 150)
    }

    @Test("A designated cover is the one loaded, not page one")
    func honoursDesignatedCover() async throws {
        let (publication, url) = try await publication("comics/manga-metadata.cbz")
        #expect(publication.coverPath == "p2.png")
        let data = try await CoverLoader.coverData(for: publication, at: url)
        // Page 2 is hue(2); page 1 is hue(1). Loading the wrong one would still
        // produce a valid image, which is why the colour is what gets asserted.
        let expected = try await ComicArchiveOpener.open(fileAt: url)
        let page = try #require(expected.pages.first { $0.path == "p2.png" })
        #expect(try await expected.data(for: page) == data)
    }

    @Test("A cover is bounded by the size it will be drawn at")
    func boundedByDisplaySize() async throws {
        // The whole reason the type exists: a 2000x3000 page costs 24 MB of pixels
        // to fill a grid cell a couple of hundred points across.
        let (publication, url) = try await publication("comics/large-page.cbz")
        let thumbnail = try await CoverLoader.anyCover(
            for: publication, at: url, maxPixelSize: 200
        )
        #expect(max(thumbnail.width, thumbnail.height) == 200)

        let larger = try await CoverLoader.anyCover(for: publication, at: url, maxPixelSize: 600)
        #expect(max(larger.width, larger.height) == 600)
    }

    @Test("A publication with no pages has no cover to load")
    func noCover() async throws {
        let (publication, url) = try await publication("comics/no-pages.cbz")
        #expect(publication.coverPath == nil)
        await #expect(throws: CoverLoader.CoverError.noCover) {
            _ = try await CoverLoader.coverData(for: publication, at: url)
        }
    }

    @Test("Indexing does not decode a cover")
    func indexingIsCheap() async throws {
        // `publication-formats` requires the first screen of a 10,000-item scan
        // within three seconds, which is only possible if indexing records where
        // the cover is rather than reading it. The record is a path, not an image.
        let (publication, _) = try await publication("comics/large-page.cbz")
        #expect(publication.coverPath == "p1.png")
    }

    @Test("A share's own row draws a cover through its registered scheme, not the filesystem")
    func remoteCoverReadsThroughTheRegisteredScheme() async throws {
        // `ComicArchiveOpener.open(fileAt:)` already checks a registered remote scheme
        // before falling to a local file -- this is the shelf's own path to a cover
        // asking the same question `anyCover` already answers for the reader's opener.
        // A gap here would mean a share's row on the shelf never draws a cover, the way
        // Android's `PublicationAccess.anyCover` did until it gained the same branch.
        let (publication, localURL) = try await publication("comics/natural-sort.cbz")
        let scheme = "storyarc-test-cover"
        ComicArchiveOpener.register(scheme: scheme) { _ in try FileSource(url: localURL) }
        let remoteURL = try #require(URL(string: "\(scheme)://nas.local/Comics/natural-sort.cbz"))

        let fromFile = try await CoverLoader.anyCover(for: publication, at: localURL, maxPixelSize: 200)
        let fromShare = try await CoverLoader.anyCover(for: publication, at: remoteURL, maxPixelSize: 200)

        #expect(fromShare.width == fromFile.width)
        #expect(fromShare.height == fromFile.height)
    }

    @Test("A share row with no recorded cover reads its own archive's cover")
    func shareRowWithoutCoverPath() async throws {
        // `SmbContributor` catalogues a share row from its name alone: no cover path and no
        // page count. The comic branch required a cover path, so such a row never drew one,
        // over a share or anywhere else.
        let (indexed, localURL) = try await publication("comics/natural-sort.cbz")
        let scheme = "storyarc-test-row-cover"
        ComicArchiveOpener.register(scheme: scheme) { _ in try FileSource(url: localURL) }
        let remoteURL = try #require(URL(string: "\(scheme)://nas.local/Comics/natural-sort.cbz"))
        let row = Publication(
            identity: PublicationIdentity(normalizedPath: remoteURL.absoluteString),
            format: .cbz,
            displayTitle: "Natural Sort",
            origin: .inferred
        )

        let fromRow = try await CoverLoader.coverData(for: row, at: remoteURL)
        let fromIndexed = try await CoverLoader.coverData(for: indexed, at: localURL)

        #expect(fromRow == fromIndexed)
    }
}
