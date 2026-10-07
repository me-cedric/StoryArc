import Foundation
import Testing

@testable import Formats
import StoryArcCore

/// The identifier an EPUB's package document carries, as the cover lookup reads it.
///
/// Task 6.1 of `cover-for-every-publication`: "an ISBN from an EPUB's OPF". The first
/// `dc:identifier` is usually a UUID and the ISBN is the second or third, so every one is
/// read. Android's `CoverIdentifierReaderTest` is the twin of this file.
@Suite("Cover identifier reader")
struct CoverIdentifierReaderTests {

    private func epub(_ identifiers: String...) -> Data {
        let list = identifiers.map { "<dc:identifier>\($0)</dc:identifier>" }.joined()
        let opf = """
        <package version="3.0"><metadata><dc:title>Fine Print</dc:title>\(list)</metadata>
        <manifest></manifest><spine></spine></package>
        """
        return StoredZip.build([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(
                #"<container><rootfiles><rootfile full-path="package.opf"/></rootfiles></container>"#.utf8
            )),
            ("package.opf", Data(opf.utf8)),
        ])
    }

    private func publication(_ format: PublicationFormat) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: "digest"),
            format: format,
            displayTitle: "Fine Print",
            origin: .inferred
        )
    }

    private func read(_ data: Data, as format: PublicationFormat = .epub) async -> CoverIdentifier? {
        await CoverIdentifierReader.identifier(for: publication(format), source: DataSource(data))
    }

    @Test("An ISBN behind a UUID identifier is the one read")
    func isbnBehindAUUID() async {
        let found = await read(epub("urn:uuid:5b4c1f9e-0c1d-4b5e-8f7a-1234567890ab", "urn:isbn:978-0-14-118776-1"))

        #expect(found == .isbn("9780141187761"))
    }

    @Test("A bare ISBN is read as it is")
    func bareISBN() async {
        #expect(await read(epub("9780141187761")) == .isbn("9780141187761"))
    }

    @Test("An EPUB with no ISBN among its identifiers reads none")
    func noISBN() async {
        #expect(await read(epub("urn:uuid:5b4c1f9e-0c1d-4b5e-8f7a-1234567890ab", "not-a-number")) == nil)
    }

    @Test("A file that is no EPUB reads none rather than throw")
    func notAnEpub() async {
        #expect(await read(Data(repeating: 7, count: 40)) == nil)
    }

    @Test("A comic archive carries no identifier to read")
    func comic() async {
        #expect(await read(epub("9780141187761"), as: .cbz) == nil)
    }

    @Test("An audio folder is read through its first track")
    func folderFirstTrack() async throws {
        let folder = URL.temporaryDirectory.appending(path: "tracks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: "02.mp3"))
        try id3Asin("B08G9PRS1K").write(to: folder.appending(path: "01.mp3"))

        let found = await CoverIdentifierReader.identifier(for: publication(.audioFolder), at: folder)

        #expect(found == .audibleASIN("B08G9PRS1K"))
    }

    private func id3Asin(_ asin: String) -> Data {
        let body = [UInt8](0...0) + Array("ASIN".utf8) + [0] + Array(asin.utf8)
        let frame = Array("TXXX".utf8) + [0, 0, 0, UInt8(body.count), 0, 0] + body
        return Data(Array("ID3".utf8) + [3, 0, 0, 0, 0, 0, UInt8(frame.count)] + frame)
    }
}
