import Foundation
import StoryArcCore
import Testing

@testable import Formats

/// Indexing a publication from a share's ranged source, with no local file.
///
/// Split from `PublicationIndexerTests` at its 400-line cap. Each case reads the corpus
/// through a source, which is the shape a share hands the indexer.
@Suite("Publication indexing from a share")
struct RemoteIndexingTests {
    @Test("An EPUB on a share is catalogued as a whole book that streams, not as a record")
    func remoteEpubIsABook() async throws {
        // Readium reads a remote EPUB through a resource over the source (14.15), so the
        // book is indexed from the share like a local one rather than held back as a record.
        let publication = try await PublicationIndexer.index(
            source: try FileSource(url: FixtureCorpus.url("ebooks/fixture.epub")),
            name: "fixture.epub",
            identity: PublicationIdentity(normalizedPath: "smb://nas/books/fixture.epub")
        )

        #expect(publication.format == .epub)
        #expect(publication.streaming == .streams)
        #expect(publication.origin == .embedded)
        #expect(publication.isReflowable)
    }

    @Test("A compressed RAR on a share is catalogued from its headers, not refused")
    func remoteCompressedRarIsCatalogued() async throws {
        // Before this fix, `index(source:...)` with no `decoderPath` returned a
        // bare `record(.cbr, ...)` for *every* remote RAR, never opening its
        // headers. `publication-formats` requires a remote CBR to be catalogued —
        // pages, cover, streaming capability — without transferring it. A
        // compressed page of a non-solid archive decodes from its own ranged
        // bytes, so the publication streams (close-the-audited-gaps 14.14).
        var bytes = [UInt8](try Data(contentsOf: FixtureCorpus.url("comics/rar4-store.cbr")))
        let methodOffset = RarReader.rar4Signature.count + 13 + 25
        #expect(bytes[methodOffset] == 0x30)
        bytes[methodOffset] = 0x33

        let publication = try await PublicationIndexer.index(
            source: DataSource(Data(bytes)),
            name: "share.cbr",
            identity: PublicationIdentity(normalizedPath: "share.cbr")
        )

        #expect(publication.format == .cbr)
        #expect(publication.pageCount == 3)
        #expect(publication.streaming == .streams)
    }
}
