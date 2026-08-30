public import Foundation

/// Bytes that can be read at an arbitrary offset.
///
/// The abstraction ADR-0008 is built on. Everything above it — the ZIP reader,
/// the page decoder, the reader UI — is unaware of whether the bytes came from a
/// local file, an SMB share, or an HTTP range request. That is what makes
/// streaming stop being a special case.
///
/// `async` on purpose: the local implementation does not need it, and every
/// remote one does. Retrofitting async through a parser is worse than carrying
/// it from the start.
public protocol RandomAccessSource: Sendable {
    /// Total length in bytes. Known up front for every source StoryArc targets —
    /// SMB reports it in a file-info response, HTTP in `Content-Length`.
    var length: Int64 { get }

    /// Reads up to `count` bytes from `offset`. Returns fewer only at the end of
    /// the source; never more.
    func read(offset: Int64, count: Int) async throws -> Data
}

public enum SourceError: Error, Equatable {
    /// A read reached past the end of the source. Always a bug in the caller or
    /// a lie in the file being parsed, never a normal condition.
    case outOfBounds(offset: Int64, count: Int, length: Int64)
    case unreadable
}

extension RandomAccessSource {
    /// Reads exactly `count` bytes, or throws. Parsers want this: a short read
    /// mid-structure means the file is malformed, not that the caller should
    /// retry with less.
    func readExactly(offset: Int64, count: Int) async throws -> Data {
        // The last guard before a header's numbers become a read, so the addition here
        // reports overflow instead of performing it: an offset near `Int64.max` plus a
        // count is a trap, and a trap is not something a caller can catch and report.
        guard HeaderBounds.span(offset: offset, count: Int64(count), fitsIn: length) else {
            throw SourceError.outOfBounds(offset: offset, count: count, length: length)
        }
        let data = try await read(offset: offset, count: count)
        guard data.count == count else { throw SourceError.unreadable }
        return data
    }

    /// Reads the last `count` bytes, or the whole source when it is shorter.
    func readTail(count: Int) async throws -> (data: Data, offset: Int64) {
        let size = Int64(min(Int64(count), length))
        let offset = length - size
        return (try await readExactly(offset: offset, count: Int(size)), offset)
    }
}

/// A local file, read through a seeking handle.
public struct FileSource: RandomAccessSource {
    public let length: Int64
    private let url: URL

    public init(url: URL) throws {
        self.url = url
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else { throw SourceError.unreadable }
        self.length = size.int64Value
    }

    public func read(offset: Int64, count: Int) async throws -> Data {
        // A fresh handle per read keeps the type `Sendable` without a lock. Page
        // reads are large and infrequent, so the open cost is noise next to the
        // decode that follows.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: count) ?? Data()
    }
}

/// A source backed by bytes already in memory. Used by tests, and by the sparse
/// cache once a range has been fetched.
public struct DataSource: RandomAccessSource {
    private let data: Data

    public var length: Int64 { Int64(data.count) }

    public init(_ data: Data) { self.data = data }

    public func read(offset: Int64, count: Int) async throws -> Data {
        let start = Int(offset)
        let end = min(start + count, data.count)
        guard start >= 0, start <= data.count else {
            throw SourceError.outOfBounds(offset: offset, count: count, length: length)
        }
        return data.subdata(in: start..<end)
    }
}
