import Foundation
import Testing

@testable import Formats

/// The one place libarchive is exercised.
///
/// These fixtures are vendored from libarchive's own test suite because a RAR
/// compressor is proprietary, and — more importantly — because their expected
/// contents are documented in libarchive's assertions rather than produced by our
/// decoder. Asserting against bytes our own decoder emitted would only prove it
/// agrees with itself.
@Suite("RAR decoding")
struct RarDecoderTests {
    /// libarchive's own generator for `test.bin`: each little-endian 32-bit word
    /// at index `i` is `max(0, k*k - 3*k + 1)` for `k = i + 1`. Reproduced here so
    /// the assertion is independent of the decoder under test.
    private func expectedBinContent(byteCount: Int) -> Data {
        var out = Data(capacity: byteCount)
        for index in 0..<(byteCount / 4) {
            let step = index + 1
            let value = max(0, step * step - 3 * step + 1)
            out.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian) { Array($0) })
        }
        return out
    }

    @Test("RAR5 compression decodes to the exact bytes libarchive's suite expects")
    func rar5Compressed() throws {
        let url = FixtureCorpus.url("comics/rar5-compressed.cbr")
        let data = try RarDecoder.data(forEntryAt: "test.bin", inArchiveAt: url)
        #expect(data.count == 1200)
        #expect(data == expectedBinContent(byteCount: 1200))
    }

    @Test("RAR4 compression decodes to the exact bytes libarchive's suite expects")
    func rar4Compressed() throws {
        let url = FixtureCorpus.url("comics/rar4-compressed.cbr")
        let data = try RarDecoder.data(forEntryAt: "test.txt", inArchiveAt: url)
        #expect(String(data: data, encoding: .utf8) == "test text document\r\n")
        // The same content again from a nested directory, which is where a
        // real comic's chapter folders would sit.
        let nested = try RarDecoder.data(forEntryAt: "testdir/test.txt", inArchiveAt: url)
        #expect(nested == data)
    }

    @Test("A solid RAR5 decodes every entry, which is why it is not refused")
    func solidRar5Decodes() throws {
        let url = FixtureCorpus.url("comics/rar5-solid.cbr")
        let names = try RarDecoder.entryNames(inArchiveAt: url)
        #expect(names.count == 7)
        // Reading the last entry means decompressing all the ones before it. If
        // solid support were missing this is where it would fail.
        let last = try RarDecoder.data(forEntryAt: "test6.bin", inArchiveAt: url)
        #expect(last.count == 4096)
    }

    @Test("A solid RAR4 fails in libarchive, which is why we refuse it ourselves")
    func solidRar4Fails() throws {
        let url = FixtureCorpus.url("comics/rar4-solid.cbr")
        // The exact behaviour RarComicArchive exists to pre-empt: the first entry
        // is listed, and only then does libarchive give up. A reader that trusted
        // this would show a one-page comic that breaks on the second turn.
        #expect(throws: (any Error).self) {
            _ = try RarDecoder.entryNames(inArchiveAt: url)
        }
    }

    // MARK: - Agreement with our own header reader

    @Test("Our header reader and libarchive see the same entries", arguments: [
        "rar4-store.cbr", "rar5-store.cbr", "rar5-compressed.cbr", "rar5-solid.cbr",
    ])
    func readersAgree(name: String) async throws {
        let url = FixtureCorpus.url("comics/\(name)")
        let ours = try await RarReader(source: try FileSource(url: url))
        let theirs = try RarDecoder.entryNames(inArchiveAt: url)

        // RarReader lists only files, so directory entries are filtered out of
        // libarchive's list before comparing. Everything else must match exactly:
        // if the two disagree about names or sizes, one of them is wrong and the
        // library would show a page count that the reader cannot deliver.
        let theirFiles = theirs.filter { !$0.path.hasSuffix("/") }
        #expect(ours.entries.map(\.path) == theirFiles.map(\.path), "\(name)")
        #expect(ours.entries.map { Int($0.size) } == theirFiles.map(\.size), "\(name)")
    }

    // MARK: - Failure paths

    @Test("A missing entry is named rather than returning empty data")
    func missingEntry() throws {
        let url = FixtureCorpus.url("comics/rar5-compressed.cbr")
        #expect(throws: RarDecoder.DecodeError.entryNotFound("nope.png")) {
            _ = try RarDecoder.data(forEntryAt: "nope.png", inArchiveAt: url)
        }
    }

    @Test("A file that is not a RAR is refused at open")
    func notARar() throws {
        let url = FixtureCorpus.url("comics/natural-sort.cbz")
        #expect(throws: (any Error).self) {
            _ = try RarDecoder.entryNames(inArchiveAt: url)
        }
    }

    @Test("Several entries come back from one pass over the archive")
    func multipleEntriesInOnePass() throws {
        let url = FixtureCorpus.url("comics/rar5-solid.cbr")
        let wanted: Set<String> = ["test.bin", "test3.bin", "test6.bin"]
        let found = try RarDecoder.data(forEntriesAt: wanted, inArchiveAt: url)
        #expect(Set(found.keys) == wanted)
        #expect(found["test.bin"]?.count == 1200)
        #expect(found["test6.bin"]?.count == 4096)
    }

    @Test("Asking for nothing does no work")
    func emptyRequest() throws {
        let url = FixtureCorpus.url("comics/rar5-compressed.cbr")
        #expect(try RarDecoder.data(forEntriesAt: [], inArchiveAt: url).isEmpty)
    }
}
