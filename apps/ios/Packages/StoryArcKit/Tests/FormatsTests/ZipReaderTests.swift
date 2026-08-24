import Foundation
import Testing

@testable import Formats

/// Counts what a reader actually touches, so "ranged reads" can be asserted
/// rather than asserted-about.
///
/// A locked class rather than an actor: `RandomAccessSource.length` is a
/// synchronous property, and an actor cannot satisfy that without pushing
/// isolation into every caller.
final class ReadCounter: RandomAccessSource, @unchecked Sendable {
    private let inner: any RandomAccessSource
    private let lock = NSLock()
    private var reads = 0
    private var bytes = 0

    init(_ inner: any RandomAccessSource) { self.inner = inner }

    var length: Int64 { inner.length }

    func read(offset: Int64, count: Int) async throws -> Data {
        let data = try await inner.read(offset: offset, count: count)
        lock.withLock {
            reads += 1
            bytes += data.count
        }
        return data
    }

    var stats: (reads: Int, bytes: Int) {
        lock.withLock { (reads, bytes) }
    }
}

@Suite("ZIP container reading")
struct ZipReaderTests {
    private func reader(_ name: String) async throws -> ZipReader {
        let source = try FileSource(url: FixtureCorpus.url("comics/\(name)"))
        return try await ZipReader(source: source)
    }

    @Test("DEFLATE entries inflate to their recorded size", arguments: [
        "natural-sort.cbz", "zip64.cbz", "archive-comment.cbz", "data-descriptor.cbz",
    ])
    func deflated(name: String) async throws {
        let zip = try await reader(name)
        let entry = try #require(zip.entries.first { PageOrdering.isPage(path: $0.path) })

        let data = try await zip.data(for: entry)

        #expect(data.count == Int(entry.uncompressedSize))
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47], "not a PNG — inflate produced junk")
    }

    @Test("STORED entries are returned as-is, not passed through inflate")
    func stored() async throws {
        let zip = try await reader("stored-entries.cbz")
        let entry = try #require(zip.entries.first)

        #expect(entry.isStored)
        let data = try await zip.data(for: entry)
        #expect(data.count == Int(entry.uncompressedSize))
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("Zip64 extended information is parsed")
    func zip64() async throws {
        let zip = try await reader("zip64.cbz")

        #expect(zip.entries.count == 3)
        // Every offset and size must still be sane after the 64-bit override.
        for entry in zip.entries {
            #expect(entry.localHeaderOffset >= 0)
            #expect(entry.uncompressedSize > 0)
        }
    }

    @Test("An archive comment does not hide the EOCD")
    func archiveComment() async throws {
        // The EOCD sits 646 bytes from the end of this fixture. A reader that
        // looks at a fixed tail offset instead of scanning for the signature
        // fails here, which is the whole reason the fixture exists.
        let zip = try await reader("archive-comment.cbz")

        #expect(zip.hasArchiveComment)
        #expect(zip.entries.count == 3)
    }

    @Test("With a data descriptor the central directory is the authority")
    func dataDescriptor() async throws {
        // Local headers in this fixture carry zero sizes and general-purpose
        // bit 3. A reader that trusts the local header reads zero bytes.
        let zip = try await reader("data-descriptor.cbz")

        for entry in zip.entries where PageOrdering.isPage(path: entry.path) {
            #expect(entry.compressedSize > 0, "central directory size was not used")
            let data = try await zip.data(for: entry)
            #expect(data.count == Int(entry.uncompressedSize))
        }
    }

    @Test("A truncated archive has no findable central directory")
    func truncated() async throws {
        let source = try FileSource(url: FixtureCorpus.url("comics/truncated.cbz"))

        await #expect(throws: ZipError.noCentralDirectory) {
            try await ZipReader(source: source)
        }
    }

    @Test("Reading one page touches a fraction of the archive")
    func rangedReadsAreActuallyRanged() async throws {
        // The claim ADR-0008 rests on, measured. This fixture is small, so the
        // interesting number is the *shape*: a bounded tail probe plus one entry,
        // never a full-file read. On a 400 MB archive the same shape means
        // megabytes instead of gigabytes.
        let file = try FileSource(url: FixtureCorpus.url("comics/natural-sort.cbz"))
        let counter = ReadCounter(file)

        let zip = try await ZipReader(source: counter)
        let first = try #require(zip.entries.first)
        _ = try await zip.data(for: first)

        let stats = counter.stats
        // Tail probe, local header probe, entry data. The central directory came
        // out of the tail read, which is the common case for a comic.
        #expect(stats.reads <= 4, "expected a handful of ranged reads, got \(stats.reads)")
    }

    @Test("Reads are bounds-checked against the source, not against a header")
    func boundsChecked() async throws {
        let source = DataSource(Data(repeating: 0, count: 100))

        await #expect(throws: SourceError.outOfBounds(offset: 90, count: 20, length: 100)) {
            _ = try await source.readExactly(offset: 90, count: 20)
        }
    }

    @Test("A source with no EOCD signature at all is reported as such")
    func notAZip() async throws {
        let source = DataSource(Data(repeating: 0x41, count: 1024))

        await #expect(throws: ZipError.noCentralDirectory) {
            try await ZipReader(source: source)
        }
    }

    @Test("A lying uncompressed size cannot make the reader allocate without bound")
    func inflateIsCapped() throws {
        // The size comes from the central directory, which is attacker
        // controlled. This is the guard, asserted directly.
        #expect(throws: ZipError.self) {
            _ = try ZipReader.inflate(Data([0x00]), expectedSize: -1)
        }
        #expect(try ZipReader.inflate(Data(), expectedSize: 0).isEmpty)
    }
}

@Suite("Random access sources")
struct RandomAccessSourceTests {
    @Test("A file source reports its real length and reads at an offset")
    func fileSource() async throws {
        let url = FixtureCorpus.url("comics/natural-sort.cbz")
        let source = try FileSource(url: url)
        let whole = try Data(contentsOf: url)

        #expect(source.length == Int64(whole.count))

        let middle = try await source.read(offset: 100, count: 16)
        #expect(middle == whole.subdata(in: 100..<116))
    }

    @Test("A tail read returns the last bytes and their offset")
    func tailRead() async throws {
        let source = DataSource(Data(0..<100))

        let (data, offset) = try await source.readTail(count: 10)

        #expect(offset == 90)
        #expect(Array(data) == Array(UInt8(90)..<UInt8(100)))
    }

    @Test("A tail read larger than the source returns the whole source")
    func tailLargerThanSource() async throws {
        let source = DataSource(Data(0..<10))

        let (data, offset) = try await source.readTail(count: 500)

        #expect(offset == 0)
        #expect(data.count == 10)
    }
}
