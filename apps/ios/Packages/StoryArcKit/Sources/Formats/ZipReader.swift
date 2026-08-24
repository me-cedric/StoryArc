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
    /// The archive comment length, if any. Kept because its presence is exactly
    /// what breaks a reader that assumes the EOCD is the last 22 bytes.
    public let hasArchiveComment: Bool

    private let source: any RandomAccessSource

    // Signatures, little-endian on disk.
    private static let eocdSignature: UInt32 = 0x0605_4B50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    private static let zip64EocdSignature: UInt32 = 0x0606_4B50
    private static let centralEntrySignature: UInt32 = 0x0201_4B50
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

    // MARK: - Central directory

    private static func parseCentralDirectory(_ data: Data, expectedCount: Int64) throws -> [ZipEntry] {
        var reader = ByteReader(data)
        var parsed: [ZipEntry] = []

        while reader.remaining >= 46 {
            let signature = try reader.uint32()
            guard signature == centralEntrySignature else {
                // Ran off the end of the entries. Not an error: the directory
                // may be followed by other records.
                break
            }
            try reader.skip(2 + 2)                       // versions
            let flags = try reader.uint16()
            let method = try reader.uint16()
            try reader.skip(2 + 2 + 4)                   // mod time/date, crc
            var compressedSize = Int64(try reader.uint32())
            var uncompressedSize = Int64(try reader.uint32())
            let nameLength = Int(try reader.uint16())
            let extraLength = Int(try reader.uint16())
            let commentLength = Int(try reader.uint16())
            try reader.skip(2 + 2 + 4)                   // disk start, attributes
            var localOffset = Int64(try reader.uint32())

            let isUTF8 = flags & 0x0800 != 0
            let path = try reader.string(nameLength, isUTF8: isUTF8)
            let extra = try reader.read(extraLength)
            try reader.skip(commentLength)

            // Zip64 extended information overrides whichever fields were maxed.
            if let zip64 = try parseZip64Extra(
                extra,
                needsUncompressed: uncompressedSize == 0xFFFF_FFFF,
                needsCompressed: compressedSize == 0xFFFF_FFFF,
                needsOffset: localOffset == 0xFFFF_FFFF
            ) {
                if let value = zip64.uncompressedSize { uncompressedSize = value }
                if let value = zip64.compressedSize { compressedSize = value }
                if let value = zip64.localOffset { localOffset = value }
            }

            parsed.append(
                ZipEntry(
                    path: path,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset,
                    compressionMethod: method,
                    isEncrypted: flags & 0x0001 != 0
                )
            )
        }

        // A count mismatch means a damaged directory. Returning what parsed is
        // more useful than refusing the archive, and the caller can compare.
        _ = expectedCount
        return parsed
    }

    private struct Zip64Fields {
        var uncompressedSize: Int64?
        var compressedSize: Int64?
        var localOffset: Int64?
    }

    /// Walks the extra-field blocks looking for header id 0x0001. Its payload
    /// carries only the fields that were sentinel-valued, in a fixed order.
    private static func parseZip64Extra(
        _ extra: Data,
        needsUncompressed: Bool,
        needsCompressed: Bool,
        needsOffset: Bool
    ) throws -> Zip64Fields? {
        guard needsUncompressed || needsCompressed || needsOffset else { return nil }

        var reader = ByteReader(extra)
        while reader.remaining >= 4 {
            let headerID = try reader.uint16()
            let size = Int(try reader.uint16())
            guard reader.remaining >= size else { break }
            guard headerID == 0x0001 else {
                try reader.skip(size)
                continue
            }
            var fields = Zip64Fields()
            var consumed = 0
            if needsUncompressed, size - consumed >= 8 {
                fields.uncompressedSize = Int64(bitPattern: try reader.uint64())
                consumed += 8
            }
            if needsCompressed, size - consumed >= 8 {
                fields.compressedSize = Int64(bitPattern: try reader.uint64())
                consumed += 8
            }
            if needsOffset, size - consumed >= 8 {
                fields.localOffset = Int64(bitPattern: try reader.uint64())
                consumed += 8
            }
            return fields
        }
        return nil
    }

    private struct Zip64Directory {
        let entryCount: Int64
        let size: Int64
        let offset: Int64
    }

    private static func readZip64(
        tail: Data,
        tailOffset: Int64,
        source: any RandomAccessSource
    ) async throws -> Zip64Directory? {
        guard let locatorIndex = lastIndex(of: zip64LocatorSignature, in: tail) else { return nil }
        var locator = ByteReader(tail, at: locatorIndex)
        _ = try locator.uint32()      // signature
        try locator.skip(4)           // disk holding the zip64 EOCD
        let recordOffset = Int64(bitPattern: try locator.uint64())

        guard recordOffset >= 0, recordOffset + 56 <= source.length else {
            throw ZipError.malformed("zip64 EOCD offset outside the source")
        }

        let record: Data
        if recordOffset >= tailOffset {
            let start = Int(recordOffset - tailOffset)
            record = tail.subdata(in: start..<min(start + 56, tail.count))
        } else {
            record = try await source.readExactly(offset: recordOffset, count: 56)
        }

        var reader = ByteReader(record)
        guard try reader.uint32() == zip64EocdSignature else {
            throw ZipError.malformed("zip64 EOCD signature missing")
        }
        try reader.skip(8 + 2 + 2 + 4 + 4)   // record size, versions, disk numbers
        try reader.skip(8)                   // entries on this disk
        let entryCount = Int64(bitPattern: try reader.uint64())
        let size = Int64(bitPattern: try reader.uint64())
        let offset = Int64(bitPattern: try reader.uint64())
        return Zip64Directory(entryCount: entryCount, size: size, offset: offset)
    }

    /// Scans backwards for a four-byte little-endian signature.
    ///
    /// Backwards and by signature, not at a fixed offset: an archive comment
    /// pushes the EOCD arbitrarily far from the tail, and `archive-comment.cbz`
    /// in the corpus exists to catch a reader that forgets.
    private static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
        let pattern: [UInt8] = [
            UInt8(signature & 0xFF),
            UInt8((signature >> 8) & 0xFF),
            UInt8((signature >> 16) & 0xFF),
            UInt8((signature >> 24) & 0xFF),
        ]
        guard data.count >= pattern.count else { return nil }
        let bytes = [UInt8](data)
        var index = bytes.count - pattern.count
        while index >= 0 {
            if bytes[index] == pattern[0],
               bytes[index + 1] == pattern[1],
               bytes[index + 2] == pattern[2],
               bytes[index + 3] == pattern[3] {
                return index
            }
            index -= 1
        }
        return nil
    }

    // MARK: - Inflate

    /// Raw DEFLATE, via the platform. We parse the container; we do not implement
    /// compression (ADR-0008).
    static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw ZipError.malformed("negative uncompressed size") }
        guard expectedSize > 0 else { return Data() }

        // `expectedSize` comes from the central directory, so it is attacker
        // controlled. Capped so a lying header cannot make us allocate the world.
        let capacity = min(expectedSize, 512 * 1024 * 1024)
        var output = Data(count: capacity)

        let written: Int = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { origin in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let originBase = origin.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    originBase, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { throw ZipError.inflateFailed }
        return output.prefix(written)
    }
}
