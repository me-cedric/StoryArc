import Foundation
import Testing

@testable import Formats

/// Asserted against the shared corpus in `packages/test-fixtures`. Android's
/// `RarReaderTest` asserts the same things about the same files.
///
/// These fixtures are store-mode, which is exactly the point: the reader parses
/// headers and reads stored bytes, and a compressed entry is the one case it
/// hands on to a decoder. See `RarReader` for why that split exists.
@Suite("RAR container reading")
struct RarReaderTests {
    private func reader(_ name: String) async throws -> RarReader {
        try await RarReader(source: try FileSource(url: FixtureCorpus.url("comics/\(name)")))
    }

    @Test("RAR4 and RAR5 are told apart, not lumped together as .cbr", arguments: [
        ("rar4-store.cbr", RarGeneration.rar4),
        ("rar5-store.cbr", RarGeneration.rar5),
        ("rar4-solid.cbr", RarGeneration.rar4),
    ])
    func generation(name: String, expected: RarGeneration) async throws {
        #expect(try await reader(name).generation == expected)
    }

    @Test("Entries carry their names and unpacked sizes", arguments: [
        "rar4-store.cbr", "rar5-store.cbr",
    ])
    func entriesMatchManifest(name: String) async throws {
        let reader = try await reader(name)
        let fixture = FixtureCorpus.comic(name)
        #expect(reader.entries.map(\.path) == fixture.expectedPageOrder)
        #expect(reader.entries.allSatisfy { $0.size > 0 })
    }

    @Test("A stored entry's bytes come back without a decoder", arguments: [
        "rar4-store.cbr", "rar5-store.cbr",
    ])
    func storedDataRoundTrips(name: String) async throws {
        let reader = try await reader(name)
        let entry = try #require(reader.entries.first)
        #expect(entry.isStored)
        let data = try await reader.data(for: entry)
        #expect(data.count == Int(entry.size))
        // A PNG signature proves the offset arithmetic landed on the data rather
        // than on a header.
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("A non-solid archive reports itself streamable", arguments: [
        "rar4-store.cbr", "rar5-store.cbr",
    ])
    func nonSolidIsStreamable(name: String) async throws {
        let reader = try await reader(name)
        #expect(!reader.isSolid)
        #expect(!reader.isEncrypted)
    }

    // MARK: - Solid

    @Test("A solid archive is detected from its flags, before any entry is read")
    func solidDetectedFromHeaders() async throws {
        let reader = try await reader("rar4-solid.cbr")
        let fixture = FixtureCorpus.comic("rar4-solid.cbr")
        #expect(reader.isSolid)
        #expect(fixture.isSolid == true)
        #expect(fixture.isStreamable == false)
        // The finding this pins: libarchive lists the first entry and *then*
        // fails, because the first entry of a solid archive is not itself solid.
        // Detection has to look at every entry, not just the first.
        #expect(reader.entries.first?.isSolid == false)
        #expect(reader.entries.dropFirst().contains { $0.isSolid })
    }

    @Test("A solid archive is refused by name rather than opened")
    func solidIsRefused() async throws {
        let url = FixtureCorpus.url("comics/rar4-solid.cbr")
        await #expect(throws: ComicArchiveError.solidArchive) {
            try await ComicArchiveOpener.open(fileAt: url)
        }
    }

    @Test("A compressed entry names the decoder it needs rather than failing vaguely")
    func compressedEntryNeedsDecoder() async throws {
        // Same fixture, with the method nibble flipped from store to LZ. The
        // headers stay valid, so this isolates the one case a decoder is for.
        var bytes = [UInt8](try Data(contentsOf: FixtureCorpus.url("comics/rar4-store.cbr")))
        // signature, then the 13-byte main header, then METHOD at offset 25
        // inside the file header.
        let methodOffset = RarReader.rar4Signature.count + 13 + 25
        #expect(bytes[methodOffset] == 0x30, "expected the store method byte here")
        bytes[methodOffset] = 0x33
        let reader = try await RarReader(source: DataSource(Data(bytes)))
        let entry = try #require(reader.entries.first)
        #expect(!entry.isStored)
        await #expect(throws: RarError.needsDecoder(method: 1)) {
            _ = try await reader.data(for: entry)
        }
    }

    // MARK: - Untrusted input

    @Test("A signature with nothing behind it yields no entries, not a crash")
    func signatureOnly() async throws {
        let reader = try await RarReader(source: DataSource(Data(RarReader.rar5Signature)))
        #expect(reader.entries.isEmpty)
    }

    @Test("Bytes that are not a RAR are rejected as such")
    func notRar() async throws {
        await #expect(throws: RarError.notRar) {
            _ = try await RarReader(source: DataSource(Data(repeating: 0x41, count: 512)))
        }
    }

    @Test("A header claiming a size past the end of the file stops the walk")
    func oversizedHeader() async throws {
        var bytes = RarReader.rar5Signature
        bytes += [0, 0, 0, 0]              // header CRC
        bytes += [0xFF, 0xFF, 0xFF, 0x7F]  // a header size far larger than the file
        let reader = try await RarReader(source: DataSource(Data(bytes)))
        #expect(reader.entries.isEmpty)
    }

    @Test("A run of continuation bytes cannot spin the vint reader")
    func vintTerminates() {
        var cursor = 0
        #expect(RarReader.vint([UInt8](repeating: 0x80, count: 64), &cursor) == nil)
        #expect(cursor <= 10)
    }
}
