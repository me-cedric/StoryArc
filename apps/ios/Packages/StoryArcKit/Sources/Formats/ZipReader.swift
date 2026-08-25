public import Foundation

internal import Compression

public enum ZipError: Error, Equatable {
    /// No End of Central Directory record found. Either not a ZIP, or truncated.
    case noCentralDirectory
    case malformed(String)
    /// General-purpose bit 0 is set. `publication-formats` requires StoryArc to
    /// say the archive is protected rather than prompt for a password.
    case encrypted
    case unsupportedCompression(UInt16)
    case inflateFailed
}

/// One entry, as described by the central directory.
///
/// **The central directory is the only authority.** Local headers are read for
/// their name and extra-field lengths and never trusted for sizes — with a data
/// descriptor they legitimately contain zeros. ADR-0008's central rule.
public struct ZipEntry: Sendable, Equatable {
    public let path: String
    public let compressedSize: Int64
    public let uncompressedSize: Int64
    public let localHeaderOffset: Int64
    public let compressionMethod: UInt16
    public let isEncrypted: Bool

    public var isStored: Bool { compressionMethod == 0 }
    public var isDeflated: Bool { compressionMethod == 8 }
}

/// Reads a ZIP's index and individual entries with ranged reads.
///
/// Three reads get any single entry out of an arbitrarily large archive: the
/// tail, the central directory if it did not fit in the tail, then the entry
/// itself. For a 400 MB comic that is megabytes, not gigabytes — which is what
/// makes the `network-share` streaming requirement achievable (ADR-0008).
public struct ZipReader: Sendable {
    public let entries: [ZipEntry]
    /// True when the index was rebuilt by scanning rather than read from a central
    /// directory. Sizes then come from local headers, which are less trustworthy —
    /// so a caller that cares can say "recovered" rather than pretending.
    public private(set) var isRecovered = false
    /// The archive comment length, if any. Kept because its presence is exactly
    /// what breaks a reader that assumes the EOCD is the last 22 bytes.
    public let hasArchiveComment: Bool

    private let source: any RandomAccessSource

    // Signatures, little-endian on disk.
    private static let eocdSignature: UInt32 = 0x0605_4B50
    static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    static let zip64EocdSignature: UInt32 = 0x0606_4B50
    static let centralEntrySignature: UInt32 = 0x0201_4B50
    private static let localHeaderSignature: UInt32 = 0x0403_4B50

    /// The EOCD is at most 22 bytes plus a comment of up to 65,535. Reading 64 KB
    /// covers the overwhelming majority of real archives and usually contains the
    /// whole central directory too, collapsing three reads into two.
    static let tailProbeSize = 64 * 1024

    public init(source: any RandomAccessSource) async throws {
        self.source = source

        let (tail, tailOffset) = try await source.readTail(count: Self.tailProbeSize + 22)
        guard let eocdIndex = Self.lastIndex(of: Self.eocdSignature, in: tail) else {
            throw ZipError.noCentralDirectory
        }

        var reader = ByteReader(tail, at: eocdIndex)
        _ = try reader.uint32()          // signature
        try reader.skip(2 + 2 + 2)       // disk numbers, entries on this disk
        let entryCount16 = try reader.uint16()
        let cdSize32 = try reader.uint32()
        let cdOffset32 = try reader.uint32()
        let commentLength = try reader.uint16()

        var entryCount = Int64(entryCount16)
        var cdSize = Int64(cdSize32)
        var cdOffset = Int64(cdOffset32)

        // Any sentinel means the real values live in the Zip64 record.
        let needsZip64 = entryCount16 == 0xFFFF || cdSize32 == 0xFFFF_FFFF || cdOffset32 == 0xFFFF_FFFF
        if needsZip64 || Self.lastIndex(of: Self.zip64LocatorSignature, in: tail) != nil {
            if let zip64 = try await Self.readZip64(tail: tail, tailOffset: tailOffset, source: source) {
                entryCount = zip64.entryCount
                cdSize = zip64.size
                cdOffset = zip64.offset
            } else if needsZip64 {
                throw ZipError.malformed("zip64 sentinel present but no zip64 record")
            }
        }

        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= source.length else {
            throw ZipError.malformed("central directory outside the source")
        }

        // If the tail already covers the central directory, slice it rather than
        // issuing a second read. Most comic archives land here.
        let directory: Data
        if cdOffset >= tailOffset {
            let start = Int(cdOffset - tailOffset)
            let end = min(start + Int(cdSize), tail.count)
            guard start <= end else { throw ZipError.malformed("central directory slice invalid") }
            directory = tail.subdata(in: start..<end)
        } else {
            directory = try await source.readExactly(offset: cdOffset, count: Int(cdSize))
        }

        self.entries = try Self.parseCentralDirectory(directory, expectedCount: entryCount)
        self.hasArchiveComment = commentLength > 0
    }

    // MARK: - Recovery

    // Recovery walks local headers one at a time, and every early exit here is a
    // different way a truncated archive ends. Splitting it hides which is which.
    // The pair rather than `disable:next`, so the doc comment below stays attached
    // to the declaration.
    // swiftlint:disable cyclomatic_complexity function_body_length

    /// Rebuilds an index by scanning for local file headers.
    ///
    /// For an archive whose central directory is gone — a truncated download, a
    /// partial copy off a failing disk. `publication-formats` requires opening
    /// whatever pages can be read and reporting what was skipped, rather than
    /// refusing the publication, and ADR-0008 notes that owning the reader is what
    /// makes this possible at all.
    ///
    /// It reads the archive **linearly**, which is inherent: recovery exists
    /// precisely because there is no index to seek with. That is the one place this
    /// reader gives up the ranged-read property, and it is why it is a separate
    /// entry point rather than a silent fallback.
    ///
    /// Local headers are trusted here for sizes, which ADR-0008 otherwise forbids —
    /// because in recovery there is nothing better. Where a header declares no size
    /// (a data descriptor was used), the entry runs to the next signature.
    public static func recovering(source: any RandomAccessSource) async throws -> ZipReader {
        var found: [ZipEntry] = []
        var offset: Int64 = 0
        // A comic has hundreds of entries. Tens of thousands is a crafted file.
        let entryLimit = 50_000
        // Read in windows with an overlap, so a signature straddling a boundary is
        // still seen whole.
        let window = 1 << 20
        let overlap = 4

        var pending: (entry: ZipEntry, dataOffset: Int64)?

        while offset < source.length, found.count < entryLimit {
            let count = Int(min(Int64(window), source.length - offset))
            let chunk = try await source.readExactly(offset: offset, count: count)
            var index = 0
            let bytes = Array(chunk)

            while index + 4 <= bytes.count {
                guard bytes[index] == 0x50, bytes[index + 1] == 0x4B else {
                    index += 1
                    continue
                }
                let at = offset + Int64(index)
                let third = bytes[index + 2]
                let fourth = bytes[index + 3]

                // A central-directory or EOCD signature ends the entry region.
                if third == 0x01 || third == 0x05 || third == 0x06 {
                    if let waiting = pending {
                        Self.append(&found, waiting, endingAt: at, source: source)
                        pending = nil
                    }
                    return ZipReader(entries: found, hasArchiveComment: false, source: source, recovered: true)
                }

                guard third == 0x03, fourth == 0x04 else {
                    index += 1
                    continue
                }

                // A previous entry with no declared size ends where this one starts.
                if let waiting = pending {
                    Self.append(&found, waiting, endingAt: at, source: source)
                    pending = nil
                }

                if let parsed = try? await Self.localEntry(at: at, source: source) {
                    if parsed.entry.compressedSize > 0 {
                        Self.append(&found, parsed, endingAt: nil, source: source)
                    } else {
                        // Size unknown until the next signature is found.
                        pending = parsed
                    }
                    index += 4
                } else {
                    index += 1
                }
            }

            if source.length - offset <= Int64(count) { break }
            offset += Int64(count - overlap)
        }

        if let waiting = pending {
            // The last entry runs to the end of what survived.
            Self.append(&found, waiting, endingAt: source.length, source: source)
        }
        guard !found.isEmpty else { throw ZipError.noCentralDirectory }
        return ZipReader(entries: found, hasArchiveComment: false, source: source, recovered: true)
    }

    /// Adds an entry, dropping it when its data does not fit in what survived.
    ///
    /// A truncated archive's final entry is the common case: its header is intact
    /// and its bytes are not. Dropping it is what makes "opened 10, skipped 2"
    /// truthful rather than a promise the reader cannot keep.
    private static func append(
        _ found: inout [ZipEntry],
        _ parsed: (entry: ZipEntry, dataOffset: Int64),
        endingAt end: Int64?,
        source: any RandomAccessSource
    ) {
        var entry = parsed.entry
        if let end {
            let available = end - parsed.dataOffset
            guard available > 0 else { return }
            entry = ZipEntry(
                path: entry.path,
                compressedSize: available,
                // Unknown without inflating. Zero means "ask the decoder", and
                // callers treat a zero-length page as skipped, so it must not be
                // used as a page size.
                uncompressedSize: entry.uncompressedSize,
                localHeaderOffset: entry.localHeaderOffset,
                compressionMethod: entry.compressionMethod,
                isEncrypted: entry.isEncrypted
            )
        }
        guard parsed.dataOffset + entry.compressedSize <= source.length else { return }
        found.append(entry)
    }

    /// Parses one local file header. Returns the entry and where its data starts.
    private static func localEntry(
        at offset: Int64, source: any RandomAccessSource
    ) async throws -> (entry: ZipEntry, dataOffset: Int64) {
        let header = try await source.readExactly(
            offset: offset, count: Int(min(30, source.length - offset))
        )
        var reader = ByteReader(header)
        guard try reader.uint32() == localHeaderSignature else {
            throw ZipError.malformed("not a local header")
        }
        try reader.skip(2)                       // version needed
        let flags = try reader.uint16()
        let method = try reader.uint16()
        try reader.skip(2 + 2 + 4)               // time, date, crc
        let compressed = Int64(try reader.uint32())
        let uncompressed = Int64(try reader.uint32())
        let nameLength = Int(try reader.uint16())
        let extraLength = Int(try reader.uint16())

        guard nameLength > 0, nameLength <= 4096 else {
            throw ZipError.malformed("implausible name length")
        }
        let nameData = try await source.readExactly(offset: offset + 30, count: nameLength)
        var nameReader = ByteReader(nameData)
        let path = try nameReader.string(nameLength, isUTF8: flags & 0x0800 != 0)

        let dataOffset = offset + 30 + Int64(nameLength) + Int64(extraLength)
        guard dataOffset <= source.length else {
            throw ZipError.malformed("local header runs past the source")
        }
        return (
            ZipEntry(
                path: path,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: offset,
                compressionMethod: method,
                isEncrypted: flags & 0x0001 != 0
            ),
            dataOffset
        )
    }

    private init(
        entries: [ZipEntry],
        hasArchiveComment: Bool,
        source: any RandomAccessSource,
        recovered: Bool
    ) {
        self.entries = entries
        self.hasArchiveComment = hasArchiveComment
        self.source = source
        self.isRecovered = recovered
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    // MARK: - Reading an entry

    /// The uncompressed bytes of one entry.
    public func data(for entry: ZipEntry) async throws -> Data {
        if entry.isEncrypted { throw ZipError.encrypted }

        // The local header's own name and extra lengths tell us where the data
        // starts. Its size fields are ignored — see ZipEntry.
        let headerProbe = try await source.readExactly(
            offset: entry.localHeaderOffset,
            count: min(30, Int(source.length - entry.localHeaderOffset))
        )
        var reader = ByteReader(headerProbe)
        guard try reader.uint32() == Self.localHeaderSignature else {
            throw ZipError.malformed("local header signature missing")
        }
        try reader.skip(2 + 2 + 2 + 2 + 2 + 4 + 4 + 4)  // version…sizes, all untrusted
        let nameLength = Int(try reader.uint16())
        let extraLength = Int(try reader.uint16())

        let dataOffset = entry.localHeaderOffset + 30 + Int64(nameLength) + Int64(extraLength)
        guard dataOffset + entry.compressedSize <= source.length else {
            throw ZipError.malformed("entry data outside the source")
        }

        let compressed = try await source.readExactly(
            offset: dataOffset,
            count: Int(entry.compressedSize)
        )

        if entry.isStored { return compressed }
        guard entry.isDeflated else { throw ZipError.unsupportedCompression(entry.compressionMethod) }
        return try Self.inflate(compressed, expectedSize: Int(entry.uncompressedSize))
    }

    public func entry(named path: String) -> ZipEntry? {
        entries.first { $0.path == path }
    }
}
