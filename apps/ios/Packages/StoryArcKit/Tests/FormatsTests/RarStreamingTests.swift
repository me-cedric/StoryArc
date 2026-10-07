import Foundation
import StoryArcCore
import Testing

@testable import Formats

/// A non-solid CBR streams: a compressed page decodes from its own ranged bytes.
///
/// `publication-formats` marks a non-solid CBR as *Streams* and a solid RAR5 as
/// *Download only*. Each test counts what the ranged source reads, so a decode that fell
/// back to the whole file fails by name. Android's `RarStreamingTest` asserts the same
/// slices from the same fixtures.
@Suite("RAR streaming from ranged reads")
struct RarStreamingTests {

    // MARK: - Non-solid

    @Test("A compressed RAR5 page decodes from its own ranged bytes, and from nothing else")
    func rar5PageStreams() async throws {
        let bytes = try await Self.storedPagesThenCompressedPage()
        let source = RangeCountingSource(bytes)
        let archive = try await RarComicArchive(source: source)
        #expect(archive.isStreamable)
        #expect(!archive.isDownloadOnly)
        #expect(PublicationIndexer.streaming(of: archive) == .streams)

        let reader = try await RarReader(source: DataSource(bytes))
        let compressed = try #require(reader.entries.first { $0.path == "test.png" })
        let stored = reader.entries.filter(\.isStored)
        #expect(stored.count == 3)

        source.reset()
        let page = try #require(archive.pages.first { $0.path == "test.png" })
        let data = try await archive.data(for: page)

        #expect(data == RarStreamingFixtures.expectedBinContent(byteCount: 1200))
        #expect(source.bytesRead == Int(reader.mainHeaderEnd + compressed.dataOffset
            + compressed.packedSize - compressed.headerOffset))
        #expect(source.bytesRead < bytes.count)
        for entry in stored {
            #expect(
                !source.touched(entry.dataOffset..<(entry.dataOffset + entry.packedSize)),
                "decoding test.png read the bytes of \(entry.path)"
            )
        }
    }

    @Test("A RAR4 entry decodes from its own ranged bytes, without the entry before it")
    func rar4EntryDecodesAlone() async throws {
        // The corpus has no compressed RAR4: libarchive's own `rar4-compressed.cbr` stores
        // its entries. libarchive still has to accept the isolated main header and file
        // header, which is the RAR4 half of the route.
        let bytes = try RarStreamingFixtures.load("rar4-compressed.cbr")
        let source = RangeCountingSource(bytes)
        let reader = try await RarReader(source: source)
        let first = try #require(reader.entries.first)
        let nested = try #require(reader.entries.first { $0.path == "testdir\\test.txt" })

        source.reset()
        let data = try RarDecoder.data(ofIsolated: nested.path, in: try await reader.isolated(nested))

        #expect(String(data: data, encoding: .utf8) == "test text document\r\n")
        #expect(!source.touched(first.dataOffset..<(first.dataOffset + first.packedSize)))
        #expect(source.bytesRead == Int(reader.mainHeaderEnd + nested.dataOffset
            + nested.packedSize - nested.headerOffset))
    }

    // MARK: - Solid

    @Test("A solid RAR5 stays download-only, and its compressed entries do not decode by range")
    func solidRar5StaysDownloadOnly() async throws {
        let url = FixtureCorpus.url("comics/rar5-solid.cbr")
        let archive = try await RarComicArchive(source: try FileSource(url: url))
        #expect(PublicationIndexer.streaming(of: archive) == .downloadOnly)

        let indexed = try await PublicationIndexer.index(
            source: try FileSource(url: url), name: "rar5-solid.cbr",
            identity: PublicationIdentity(normalizedPath: "smb://host/share/rar5-solid.cbr")
        )
        #expect(indexed.streaming == .downloadOnly)

        // The same archive with one entry named as a page: it is listed, and it is not
        // decoded from ranges, because every entry before it would be needed.
        let bytes = try await RarStreamingFixtures.renamed(
            RarStreamingFixtures.load("rar5-solid.cbr"), ["test3.bin": "test3.png"]
        )
        let source = RangeCountingSource(bytes)
        let withPage = try await RarComicArchive(source: source)
        #expect(withPage.isDownloadOnly)
        let page = try #require(withPage.pages.first)
        source.reset()
        await #expect(throws: ComicArchiveError.unsupportedContainer(.rar)) {
            _ = try await withPage.data(for: page)
        }
        #expect(source.bytesRead == 0)
    }

    @Test("A solid RAR4 is still refused over a share")
    func solidRar4StaysRefused() async throws {
        let url = FixtureCorpus.url("comics/rar4-solid.cbr")
        let indexed = try await PublicationIndexer.index(
            source: try FileSource(url: url), name: "rar4-solid.cbr",
            identity: PublicationIdentity(normalizedPath: "smb://host/share/rar4-solid.cbr")
        )
        #expect(indexed.streaming == .refused)
    }

    // MARK: - Untrusted input

    @Test("An entry whose packed bytes run past the source is refused before any read")
    func isolatedEntryIsBounded() async throws {
        let bytes = try RarStreamingFixtures.load("rar5-compressed.cbr")
        let reader = try await RarReader(source: DataSource(bytes))
        let entry = try #require(reader.entries.first)
        let liar = RarEntry(
            path: entry.path, size: entry.size, packedSize: Int64(bytes.count),
            dataOffset: entry.dataOffset, isStored: false, isSolid: false,
            isEncrypted: false, headerOffset: entry.headerOffset
        )
        await #expect(throws: RarError.self) { _ = try await reader.isolated(liar) }
    }

    /// `rar5-store.cbr`'s three stored pages, then `rar5-compressed.cbr`'s compressed entry
    /// renamed to an image, then the end block. Every block is copied whole from a fixture,
    /// so the only bytes this writes are one name and its header CRC.
    static func storedPagesThenCompressedPage() async throws -> Data {
        let store = try RarStreamingFixtures.load("rar5-store.cbr")
        let compressed = try await RarStreamingFixtures.renamed(
            RarStreamingFixtures.load("rar5-compressed.cbr"), ["test.bin": "test.png"]
        )
        let storeEntries = try await RarReader(source: DataSource(store)).entries
        let entry = try #require(try await RarReader(source: DataSource(compressed)).entries.first)
        let last = try #require(storeEntries.last)
        let pagesEnd = Int(last.dataOffset + last.packedSize)
        var out = Data(store[0..<pagesEnd])
        out.append(compressed[Int(entry.headerOffset)..<Int(entry.dataOffset + entry.packedSize)])
        out.append(store[pagesEnd...])
        return out
    }
}

/// Counts every byte a decode asks for, and where.
private final class RangeCountingSource: RandomAccessSource, @unchecked Sendable {
    private let data: Data
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    init(_ data: Data) { self.data = data }

    var length: Int64 { Int64(data.count) }

    var bytesRead: Int { lock.withLock { ranges.reduce(0) { $0 + $1.count } } }

    func reset() { lock.withLock { ranges = [] } }

    func touched(_ range: Range<Int64>) -> Bool {
        lock.withLock { ranges.contains { $0.overlaps(range) } }
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        let end = min(Int(offset) + count, data.count)
        guard offset >= 0, Int(offset) <= end else {
            throw SourceError.outOfBounds(offset: offset, count: count, length: length)
        }
        lock.withLock { ranges.append(offset..<Int64(end)) }
        return data.subdata(in: Int(offset)..<end)
    }
}
