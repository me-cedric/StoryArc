import Foundation
import Testing

import Formats
import ReadiumShared
import ReadiumStreamer
@testable import EpubReaderFeature

/// A reflowable EPUB on a share streams: Readium reads it through ``SourceResource``, and
/// the bytes the source hands out are counted (close-the-audited-gaps 14.15).
///
/// The book carries 40 MB of bytes that no chapter names. Readium reads a ZIP under 5 MB
/// whole, and reads a remote one in windows of 6 MB, so a smaller book could not tell
/// streaming from a whole fetch. Android's `EpubStreamingTest` builds the same kind of book.
@Suite("EPUB streaming from a ranged source")
struct EpubStreamingTests {

    @Test("A remote EPUB opens and reads a chapter without the whole file")
    func remoteEpubStreams() async throws {
        let bytes = PaddedEpub.make(padding: 40 * 1024 * 1024)
        let source = CountingSource(bytes)
        ComicArchiveOpener.register(scheme: Self.scheme) { _ in source }
        let url = try #require(URL(string: "\(Self.scheme)://nas/books/padded.epub"))

        let retriever = AssetRetriever(httpClient: DefaultHTTPClient())
        let asset = try #require(await EpubReaderModel.asset(for: url, retriever: retriever))
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: DefaultHTTPClient(),
                assetRetriever: retriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
        let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
        let chapter = try #require(publication.readingOrder.first)
        let data = try #require(try await publication.get(chapter)?.read().get())

        #expect(String(bytes: data, encoding: .utf8)?.contains(PaddedEpub.marker) == true)
        #expect(
            source.bytesRead < bytes.count / 2,
            "Readium read \(source.bytesRead) of \(bytes.count) bytes to open one chapter"
        )
    }

    @Test("A share that cannot be reached gives no asset")
    func unreachableShareGivesNoAsset() async throws {
        ComicArchiveOpener.register(scheme: Self.unreachable) { _ in throw CancellationError() }
        let url = try #require(URL(string: "\(Self.unreachable)://nas/books/padded.epub"))

        let asset = await EpubReaderModel.asset(
            for: url, retriever: AssetRetriever(httpClient: DefaultHTTPClient())
        )

        #expect(asset == nil)
    }

    private static let scheme = "storyarc-epub-test"
    private static let unreachable = "storyarc-epub-unreachable"
}

/// Counts every byte a read hands out.
private final class CountingSource: RandomAccessSource, @unchecked Sendable {
    private let data: Data
    private let lock = NSLock()
    private var count = 0

    init(_ data: Data) { self.data = data }

    var length: Int64 { Int64(data.count) }

    var bytesRead: Int { lock.withLock { count } }

    func read(offset: Int64, count wanted: Int) async throws -> Data {
        let start = Int(offset)
        let end = min(start + wanted, data.count)
        guard start >= 0, start <= end else { return Data() }
        lock.withLock { count += end - start }
        return data.subdata(in: start..<end)
    }
}

/// A two-chapter EPUB, stored without compression, with an unreferenced entry of zeros
/// between the `mimetype` and the rest.
private enum PaddedEpub {
    static let marker = "Streamed chapter one"

    static func make(padding: Int) -> Data {
        var zip = ZipWriter()
        zip.add("mimetype", Data("application/epub+zip".utf8))
        zip.add("OEBPS/unreferenced.bin", Data(count: padding), crc: 0)
        zip.add("META-INF/container.xml", Data("""
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8))
        zip.add("OEBPS/package.opf", Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="id">padded</dc:identifier><dc:title>Padded</dc:title><dc:language>en</dc:language>
            <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>
        </package>
        """.utf8))
        let toc = "<nav epub:type=\"toc\"><ol><li><a href=\"ch1.xhtml\">One</a></li></ol></nav>"
        zip.add("OEBPS/nav.xhtml", chapter("Contents", body: toc))
        zip.add("OEBPS/ch1.xhtml", chapter("One", body: "<p>\(marker)</p>"))
        zip.add("OEBPS/ch2.xhtml", chapter("Two", body: "<p>Chapter two</p>"))
        return zip.finish()
    }

    private static func chapter(_ title: String, body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>\(title)</title></head><body>\(body)</body></html>
        """.utf8)
    }
}

/// The smallest ZIP writer the test needs: stored entries and a central directory.
private struct ZipWriter {
    private var body = Data()
    private var directory = Data()
    private var entries: UInt16 = 0

    /// `crc` overrides the checksum for an entry nothing reads, which saves hashing 40 MB.
    mutating func add(_ name: String, _ data: Data, crc: UInt32? = nil) {
        let nameBytes = Data(name.utf8)
        let checksum = crc ?? Self.crc32(data)
        let offset = UInt32(body.count)
        var local = Data()
        local.append(le32: 0x0403_4B50)
        local.append(le16: 20); local.append(le16: 0); local.append(le16: 0)
        local.append(le16: 0); local.append(le16: 0)
        local.append(le32: checksum)
        local.append(le32: UInt32(data.count)); local.append(le32: UInt32(data.count))
        local.append(le16: UInt16(nameBytes.count)); local.append(le16: 0)
        body.append(local); body.append(nameBytes); body.append(data)

        directory.append(le32: 0x0201_4B50)
        directory.append(le16: 20); directory.append(le16: 20)
        directory.append(le16: 0); directory.append(le16: 0)
        directory.append(le16: 0); directory.append(le16: 0)
        directory.append(le32: checksum)
        directory.append(le32: UInt32(data.count)); directory.append(le32: UInt32(data.count))
        directory.append(le16: UInt16(nameBytes.count))
        directory.append(le16: 0); directory.append(le16: 0); directory.append(le16: 0)
        directory.append(le16: 0); directory.append(le32: 0)
        directory.append(le32: offset)
        directory.append(nameBytes)
        entries += 1
    }

    func finish() -> Data {
        var out = body
        out.append(directory)
        out.append(le32: 0x0605_4B50)
        out.append(le16: 0); out.append(le16: 0)
        out.append(le16: entries); out.append(le16: entries)
        out.append(le32: UInt32(directory.count)); out.append(le32: UInt32(body.count))
        out.append(le16: 0)
        return out
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
