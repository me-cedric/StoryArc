public import Foundation

// Where a ZIP says its entries are, split out of `ZipReader`.
//
// Finding and parsing the central directory is the half of the format that deals
// in offsets, ZIP64 extensions and the end-of-central-directory record. Reading
// an entry is the other half. They share a type and nothing else.

extension ZipReader {
    /// Reads the entries out of a central directory.
    ///
    /// `sourceLength` is not decoration. A zip64 extra field can override an entry's
    /// offset and compressed size with any 64-bit number, and those numbers are added to
    /// things later — so they are range-checked here, where they are parsed, rather than
    /// in the guard that would trap on them.
    static func parseCentralDirectory(
        _ data: Data, expectedCount: Int64, sourceLength: Int64
    ) throws -> [ZipEntry] {
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
            let entry = ZipEntry(
                path: path,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset,
                compressionMethod: method,
                isEncrypted: flags & 0x0001 != 0
            )
            try checkFits(entry, in: sourceLength)
            parsed.append(entry)
        }

        // A count mismatch means a damaged directory. Returning what parsed is
        // more useful than refusing the archive, and the caller can compare.
        _ = expectedCount
        return parsed
    }

    /// Refuses an entry whose zip64 override put it outside the file.
    ///
    /// The override is the only way any of these leaves the range a 32-bit field could
    /// hold, and it is unchecked on the wire. An entry that starts or ends outside the
    /// file is a lie about the archive rather than damage to it, so the archive is
    /// refused rather than half-read. `uncompressedSize` is exempt on purpose:
    /// compression is what makes a value larger than the file honest there.
    private static func checkFits(_ entry: ZipEntry, in sourceLength: Int64) throws {
        guard HeaderBounds.position(entry.localHeaderOffset, fitsIn: sourceLength),
              HeaderBounds.position(entry.compressedSize, fitsIn: sourceLength),
              entry.uncompressedSize >= 0
        else {
            throw ZipError.malformed("central directory entry outside the source")
        }
    }

    struct Zip64Fields {
        var uncompressedSize: Int64?
        var compressedSize: Int64?
        var localOffset: Int64?
    }

    /// Walks the extra-field blocks looking for header id 0x0001. Its payload
    /// carries only the fields that were sentinel-valued, in a fixed order.
    static func parseZip64Extra(
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

    struct Zip64Directory {
        let entryCount: Int64
        let size: Int64
        let offset: Int64
    }

    static func readZip64(
        tail: Data,
        tailOffset: Int64,
        source: any RandomAccessSource
    ) async throws -> Zip64Directory? {
        guard let locatorIndex = lastIndex(of: zip64LocatorSignature, in: tail) else { return nil }
        var locator = ByteReader(tail, at: locatorIndex)
        _ = try locator.uint32()      // signature
        try locator.skip(4)           // disk holding the zip64 EOCD
        let recordOffset = Int64(bitPattern: try locator.uint64())

        // `recordOffset + 56` is the arithmetic this guard used to do itself, on a
        // number the file chose. At 0x7FFFFFFFFFFFFFC8 the addition leaves Int64 before
        // the comparison runs, and Swift aborts the process rather than throwing.
        guard HeaderBounds.span(offset: recordOffset, count: 56, fitsIn: source.length) else {
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
        // Checked here rather than by the caller: two positive values whose sum leaves
        // Int64 pass every `>= 0` test and trap on the addition that follows.
        guard entryCount >= 0,
              HeaderBounds.span(offset: offset, count: size, fitsIn: source.length)
        else {
            throw ZipError.malformed("zip64 central directory outside the source")
        }
        return Zip64Directory(entryCount: entryCount, size: size, offset: offset)
    }

    /// Scans backwards for a four-byte little-endian signature.
    ///
    /// Backwards and by signature, not at a fixed offset: an archive comment
    /// pushes the EOCD arbitrarily far from the tail, and `archive-comment.cbz`
    /// in the corpus exists to catch a reader that forgets.
    static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
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
}
