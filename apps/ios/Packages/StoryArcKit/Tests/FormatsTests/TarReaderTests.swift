import Foundation
import Testing

@testable import Formats

/// Asserted against the shared corpus in `packages/test-fixtures`. Android's
/// `TarReaderTest` asserts the same things about the same files.
@Suite("TAR container reading")
struct TarReaderTests {
    private func reader(_ name: String) async throws -> TarReader {
        try await TarReader(source: try FileSource(url: FixtureCorpus.url("comics/\(name)")))
    }

    @Test("A TAR is identified by its magic at offset 257, not by its extension")
    func detectedByContent() async throws {
        let source = try FileSource(url: FixtureCorpus.url("comics/tar-store.cbt"))
        let probe = try await source.read(offset: 0, count: FormatSniffer.probeLength)
        #expect(FormatSniffer.container(of: probe) == .tar)
    }

    @Test("The probe reaches far enough to see the TAR magic")
    func probeCoversTheMagic() {
        // If someone shrinks probeLength back to 8 for the other containers,
        // CBT detection silently stops working. This is the guard.
        #expect(FormatSniffer.probeLength >= TarReader.magicOffset + 5)
    }

    @Test("Entries keep archive order and report their real sizes")
    func entriesInOrder() async throws {
        let reader = try await reader("tar-store.cbt")
        #expect(reader.entries.map(\.path) == ["page1.png", "page2.png", "page3.png"])
        #expect(reader.entries.allSatisfy { $0.size > 0 })
    }

    @Test("Chapter directories are read as paths, and the directory blocks are not pages")
    func nestedChapters() async throws {
        let reader = try await reader("tar-nested-chapters.cbt")
        #expect(reader.entries.map(\.path) == ["ch1/p1.png", "ch1/p2.png", "ch2/p1.png"])
    }

    @Test("Entry bytes come back verbatim — TAR stores no compression")
    func dataRoundTrips() async throws {
        let reader = try await reader("tar-store.cbt")
        let entry = try #require(reader.entries.first)
        let data = try await reader.data(for: entry)
        #expect(data.count == Int(entry.size))
        // Every fixture page is a PNG, so the signature proves the offset
        // arithmetic landed on the data block rather than on a header.
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("A CBT opens through the same opener as every other container")
    func opensThroughTheOpener() async throws {
        let archive = try await ComicArchiveOpener.open(
            fileAt: FixtureCorpus.url("comics/tar-store.cbt")
        )
        let fixture = FixtureCorpus.comic("tar-store.cbt")
        #expect(archive.pages.map(\.path) == fixture.expectedPageOrder)
        #expect(archive.skippedPageCount == 0)
    }

    // MARK: - Untrusted input

    @Test("A block whose checksum does not match is not accepted as a header")
    func rejectsBadChecksum() async throws {
        var bytes = [UInt8](repeating: 0, count: 1024)
        bytes.replaceSubrange(0..<9, with: Array("page1.png".utf8))
        bytes.replaceSubrange(257..<262, with: Array("ustar".utf8))
        // Deliberately no checksum field. A parser that trusts the magic alone
        // would read a 512-byte block of zeros as an entry.
        await #expect(throws: TarError.notTar) {
            _ = try await TarReader(source: DataSource(Data(bytes)))
        }
    }

    @Test("A header claiming more bytes than the file holds yields no entry")
    func rejectsOversizedEntry() async throws {
        var header = [UInt8](repeating: 0, count: 512)
        header.replaceSubrange(0..<9, with: Array("page1.png".utf8))
        header.replaceSubrange(257..<262, with: Array("ustar".utf8))
        header[156] = 0x30  // regular file
        // 8 GB of data behind a 512-byte file.
        header.replaceSubrange(124..<135, with: Array("77777777777".utf8))
        writeChecksum(into: &header)

        let reader = try await TarReader(source: DataSource(Data(header)))
        // The header parses, so this is not "not a TAR" — but the entry cannot
        // be surfaced, because its bytes are not there.
        #expect(reader.entries.isEmpty)
    }

    @Test("An empty source is not mistaken for an empty archive")
    func rejectsEmptySource() async throws {
        await #expect(throws: TarError.notTar) {
            _ = try await TarReader(source: DataSource(Data()))
        }
    }

    /// The checksum a real TAR writer would have written for this header.
    private func writeChecksum(into header: inout [UInt8]) {
        for index in 148..<156 { header[index] = 0x20 }
        let sum = header.reduce(0) { $0 + Int($1) }
        let field = Array(String(format: "%06o", sum).utf8) + [0x00, 0x20]
        header.replaceSubrange(148..<156, with: field)
    }
}
