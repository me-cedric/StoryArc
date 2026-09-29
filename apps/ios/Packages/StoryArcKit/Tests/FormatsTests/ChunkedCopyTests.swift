import Foundation
import Testing

@testable import Formats

/// A source that counts how many times it was asked for bytes, and never answers with more
/// than it was told it may hold at once — the way a real transport actually behaves, and the
/// property a one-shot `read(offset: 0, count: Int(length))` call does not have to respect.
private final class CountingSource: RandomAccessSource, @unchecked Sendable {
    let bytes: Data
    let maxPerRead: Int
    private(set) var reads: [(offset: Int64, count: Int)] = []

    var length: Int64 { Int64(bytes.count) }

    init(bytes: Data, maxPerRead: Int) {
        self.bytes = bytes
        self.maxPerRead = maxPerRead
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        reads.append((offset, count))
        let capped = min(count, maxPerRead)
        let start = Int(offset)
        let end = min(start + capped, bytes.count)
        guard start <= bytes.count else { return Data() }
        return bytes.subdata(in: start..<end)
    }
}

/// `ChunkedCopy` is what stands between a large publication and a transport that refuses a
/// single oversized read -- SMB's own reply is capped by a `UInt32` length, and this is the
/// one place that limit is respected rather than assumed away.
@Suite("A source is copied to disk in chunks, never in one read")
struct ChunkedCopyTests {
    private static func temporaryFile() -> URL {
        URL.temporaryDirectory.appending(path: "chunked-copy-\(UUID().uuidString)")
    }

    @Test("The whole source lands on disk byte for byte")
    func copiesEveryByte() async throws {
        let bytes = Data((0..<5000).map { UInt8($0 % 256) })
        let source = CountingSource(bytes: bytes, maxPerRead: 700)
        let destination = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination) }

        try await ChunkedCopy.copy(source, to: destination, chunkSize: 1024)

        let written = try Data(contentsOf: destination)
        #expect(written == bytes)
    }

    @Test("A source larger than the chunk size is read more than once")
    func readsInChunksRatherThanOneShot() async throws {
        // The property a one-shot `read(offset: 0, count: Int(source.length))` cannot have:
        // more than one call, none of them asking for the whole length in a single message.
        let bytes = Data(repeating: 0x42, count: 10_000)
        let source = CountingSource(bytes: bytes, maxPerRead: 10_000)
        let destination = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination) }

        try await ChunkedCopy.copy(source, to: destination, chunkSize: 2000)

        #expect(source.reads.count == 5, "expected five 2000-byte reads, got \(source.reads.count)")
        #expect(source.reads.allSatisfy { $0.count <= 2000 })
    }

    @Test("No partial file is left beside a finished copy")
    func leavesNoPartialFile() async throws {
        let source = CountingSource(bytes: Data(repeating: 1, count: 100), maxPerRead: 100)
        let destination = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination) }

        try await ChunkedCopy.copy(source, to: destination)

        let partial = destination.appendingPathExtension("partial")
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test("A copy that throws mid-way leaves neither a partial nor a destination file")
    func aFailedCopyLeavesNothing() async {
        struct Boom: Error {}
        struct FailingSource: RandomAccessSource {
            let length: Int64 = 10_000
            func read(offset: Int64, count: Int) async throws -> Data {
                if offset > 0 { throw Boom() }
                return Data(repeating: 0, count: count)
            }
        }
        let destination = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination) }

        await #expect(throws: Boom.self) {
            try await ChunkedCopy.copy(FailingSource(), to: destination, chunkSize: 1000)
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathExtension("partial").path))
    }

    @Test("A source that ends before its stated length fails rather than leaving a short file")
    func aShortSourceFails() async {
        struct ShortSource: RandomAccessSource {
            let length: Int64 = 10_000
            func read(offset: Int64, count: Int) async throws -> Data {
                offset < 4_000 ? Data(repeating: 1, count: min(count, 4_000 - Int(offset))) : Data()
            }
        }
        let destination = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: destination) }

        await #expect(throws: SourceError.unreadable) {
            try await ChunkedCopy.copy(ShortSource(), to: destination, chunkSize: 1000)
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathExtension("partial").path))
    }
}
