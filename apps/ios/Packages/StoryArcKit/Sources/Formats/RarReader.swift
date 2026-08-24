public import Foundation

/// One file inside a RAR archive.
public struct RarEntry: Sendable, Equatable {
    public let path: String
    /// Size after decompression. What the page decoder will see.
    public let size: Int64
    /// Size on disk. Equal to `size` when the entry is stored.
    public let packedSize: Int64
    /// Where the entry's packed bytes start.
    public let dataOffset: Int64
    /// Stored entries carry their bytes verbatim, so they need no decoder at all.
    public let isStored: Bool
    /// Solid entries cannot be decompressed without the entries before them.
    public let isSolid: Bool
    public let isEncrypted: Bool
}

/// Which RAR format an archive uses. They share an extension and nothing else:
/// different signatures, different header layouts, different integer encodings.
public enum RarGeneration: String, Sendable {
    case rar4, rar5
}

public enum RarError: Error, Equatable {
    case malformed(String)
    case notRar
    /// The entry is compressed, and decompressing it needs a decoder StoryArc
    /// does not carry yet. Distinct from `malformed`: the archive is fine.
    case needsDecoder(method: Int)
    /// More headers than any real publication has. A guard against a crafted
    /// file that would otherwise be read into an unbounded array.
    case tooManyEntries
}

/// Reads RAR *headers*, and the bytes of stored entries.
///
/// Deliberately not a RAR decoder. Everything the library needs in order to
/// index a publication — page names, page sizes, the cover, whether the archive
/// is solid or encrypted — lives in the headers, and headers are a documented
/// layout with no compression in them. So this is written here, the same
/// reasoning ADR-0008 applies to ZIP, and libarchive's remaining job shrinks to
/// one function: turn a compressed entry's packed bytes into unpacked bytes.
///
/// The practical payoff is that the answers `Streaming capability per format`
/// needs are available before any C library is linked, and that a solid archive
/// is recognised from its flags rather than from a decoder failing halfway.
///
/// This parser runs on untrusted input. `SECURITY.md` names archive parsing as
/// the largest attack surface in the app: every offset is bounds-checked against
/// the source before use, no length from a header is used to allocate, and the
/// entry count is capped.
public struct RarReader: Sendable {
    public let generation: RarGeneration
    public let entries: [RarEntry]
    /// The archive-level solid flag. Individual entries carry their own.
    public let isSolidArchive: Bool
    /// Set when headers or entries are encrypted. `publication-formats` requires
    /// saying so rather than prompting for a password.
    public let isEncrypted: Bool

    private let source: any RandomAccessSource

    static let rar4Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    static let rar5Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]

    /// A comic has hundreds of pages. Tens of thousands means a crafted file.
    private static let entryLimit = 50_000
    /// Headers are small. Anything claiming more is not a header.
    private static let maxHeaderSize = 1 << 20

    /// True when any entry cannot be reached without decompressing the ones
    /// before it — the question `Streaming capability per format` asks. A solid
    /// archive is never streamable, on either generation.
    public var isSolid: Bool { isSolidArchive || entries.contains(where: \.isSolid) }

    /// Whether the archive can be read at all once it is local.
    ///
    /// This is where the two generations part company, measured rather than
    /// assumed. libarchive reads a solid RAR5 completely — its own test suite's
    /// `test_read_format_rar5_solid.rar` yields all seven entries. It cannot read
    /// a solid RAR4 at all: `read_header()` returns `ARCHIVE_FATAL` on any file
    /// header carrying `FHD_SOLID`, with no compression-method check and no
    /// fallback. So a solid RAR4 is unsupported and downloading it changes
    /// nothing, while a solid RAR5 is merely download-only.
    public var isReadableWhenLocal: Bool {
        !(isSolid && generation == .rar4)
    }

    public init(source: any RandomAccessSource) async throws {
        self.source = source
        let head = try await source.read(offset: 0, count: Self.rar5Signature.count)
        let bytes = Array(head)

        if bytes.starts(with: Self.rar5Signature) {
            self.generation = .rar5
            let parsed = try await Self.parseRar5(source: source)
            (entries, isSolidArchive, isEncrypted) = parsed
        } else if bytes.starts(with: Self.rar4Signature) {
            self.generation = .rar4
            let parsed = try await Self.parseRar4(source: source)
            (entries, isSolidArchive, isEncrypted) = parsed
        } else {
            throw RarError.notRar
        }
    }

    /// A stored entry's bytes. Compressed entries throw `needsDecoder`, which is
    /// the seam libarchive fills.
    public func data(for entry: RarEntry) async throws -> Data {
        if entry.isEncrypted { throw RarError.needsDecoder(method: -1) }
        guard entry.isStored else { throw RarError.needsDecoder(method: 1) }
        guard entry.dataOffset >= 0, entry.packedSize >= 0,
              entry.dataOffset + entry.packedSize <= source.length
        else { throw RarError.malformed("entry lies outside the source") }
        return try await source.readExactly(offset: entry.dataOffset, count: Int(entry.packedSize))
    }

    // MARK: - RAR4

    private static func parseRar4(
        source: any RandomAccessSource
    ) async throws -> ([RarEntry], Bool, Bool) {
        var entries: [RarEntry] = []
        var solidArchive = false
        var encrypted = false
        var offset = Int64(rar4Signature.count)

        while offset + 7 <= source.length {
            let head = Array(try await source.readExactly(offset: offset, count: 7))
            let flags = Int(head[3]) | Int(head[4]) << 8
            let headerSize = Int(head[5]) | Int(head[6]) << 8
            guard headerSize >= 7, headerSize <= maxHeaderSize,
                  offset + Int64(headerSize) <= source.length
            else { break }

            let type = head[2]
            if type == 0x73 {  // main archive header
                solidArchive = flags & 0x0008 != 0
                // 0x0080 means the block headers themselves are encrypted, so
                // nothing past this point can be parsed at all.
                if flags & 0x0080 != 0 { return ([], solidArchive, true) }
                offset += Int64(headerSize)
                continue
            }
            if type == 0x7B { break }  // end of archive

            guard type == 0x74 else {  // not a file header: skip it whole
                let addSize = flags & 0x8000 != 0 ? try await rar4AddSize(source, offset, headerSize) : 0
                offset += Int64(headerSize) + addSize
                continue
            }

            let header = Array(try await source.readExactly(offset: offset, count: headerSize))
            guard header.count >= 32 else { break }

            var packed = Int64(le32(header, 7))
            var unpacked = Int64(le32(header, 11))
            let method = Int(header[25])
            let nameSize = Int(header[26]) | Int(header[27]) << 8
            var cursor = 32
            if flags & 0x0100 != 0 {  // LHD_LARGE: 64-bit sizes in two halves
                guard header.count >= cursor + 8 else { break }
                packed |= Int64(le32(header, cursor)) << 32
                unpacked |= Int64(le32(header, cursor + 4)) << 32
                cursor += 8
            }
            guard nameSize >= 0, cursor + nameSize <= header.count else { break }
            let rawName = Array(header[cursor..<(cursor + nameSize)])
            let isDirectory = flags & 0x00E0 == 0x00E0
            let entryEncrypted = flags & 0x0004 != 0
            if entryEncrypted { encrypted = true }

            let dataOffset = offset + Int64(headerSize)
            if !isDirectory, packed >= 0, unpacked >= 0, dataOffset + packed <= source.length {
                guard entries.count < entryLimit else { throw RarError.tooManyEntries }
                entries.append(
                    RarEntry(
                        path: rar4Name(rawName, isUnicode: flags & 0x0200 != 0),
                        size: unpacked,
                        packedSize: packed,
                        dataOffset: dataOffset,
                        isStored: method == 0x30,
                        isSolid: flags & 0x0010 != 0,
                        isEncrypted: entryEncrypted
                    )
                )
            }
            offset = dataOffset + max(packed, 0)
        }

        guard !entries.isEmpty || solidArchive || encrypted else {
            // A signature and nothing parseable behind it.
            return ([], solidArchive, encrypted)
        }
        return (entries, solidArchive, encrypted)
    }

    /// A non-file block's payload size, which sits directly after its 7-byte head.
    private static func rar4AddSize(
        _ source: any RandomAccessSource, _ offset: Int64, _ headerSize: Int
    ) async throws -> Int64 {
        guard headerSize >= 11 else { return 0 }
        let bytes = Array(try await source.readExactly(offset: offset, count: 11))
        return Int64(le32(bytes, 7))
    }

    /// RAR4 stores a long name as `asciiName\0<packed unicode>`. The ASCII half
    /// is always present and always valid, so it is what we use.
    ///
    /// ponytail: the packed-unicode half needs RAR's own name codec. Page paths
    /// are ASCII in every comic that exists; revisit if a real file proves
    /// otherwise.
    private static func rar4Name(_ raw: [UInt8], isUnicode: Bool) -> String {
        let ascii = isUnicode ? Array(raw.prefix(while: { $0 != 0 })) : raw
        return String(bytes: ascii, encoding: .utf8)
            ?? String(bytes: ascii, encoding: .isoLatin1)
            ?? ""
    }

    private static func le32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        guard at + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8
            | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }

    // MARK: - RAR5

    private static func parseRar5(
        source: any RandomAccessSource
    ) async throws -> ([RarEntry], Bool, Bool) {
        var entries: [RarEntry] = []
        var solidArchive = false
        var encrypted = false
        var offset = Int64(rar5Signature.count)

        while offset + 8 <= source.length {
            // The header's own size is a vint, so read a window big enough to
            // hold the size field and then the header it describes.
            let window = try await source.read(offset: offset, count: 64)
            guard window.count > 4 else { break }
            var cursor = 4  // past the header CRC32
            var bytes = Array(window)
            guard let headerSize = vint(bytes, &cursor), headerSize > 0,
                  headerSize <= Int64(maxHeaderSize)
            else { break }

            let headerStart = offset + Int64(cursor)
            guard headerStart + headerSize <= source.length else { break }
            bytes = Array(try await source.readExactly(
                offset: headerStart, count: Int(headerSize)
            ))
            var read = 0

            guard let type = vint(bytes, &read), let flags = vint(bytes, &read) else { break }
            var extraSize: Int64 = 0
            var dataSize: Int64 = 0
            if flags & 0x0001 != 0, let value = vint(bytes, &read) { extraSize = value }
            if flags & 0x0002 != 0, let value = vint(bytes, &read) { dataSize = value }

            let nextOffset = headerStart + headerSize + max(dataSize, 0)
            let dataOffset = headerStart + headerSize

            switch type {
            case 1:  // main archive header
                if let archiveFlags = vint(bytes, &read) { solidArchive = archiveFlags & 0x0004 != 0 }
            case 4:  // encrypted headers: nothing past this point can be parsed
                return ([], solidArchive, true)
            case 5:  // end of archive
                return (entries, solidArchive, encrypted)
            case 2, 3:  // file, and service headers such as the archive comment
                guard let fileFlags = vint(bytes, &read),
                      let unpacked = vint(bytes, &read),
                      vint(bytes, &read) != nil  // attributes
                else { break }
                if fileFlags & 0x0002 != 0 { read += 4 }  // mtime
                if fileFlags & 0x0004 != 0 { read += 4 }  // data CRC32
                guard let compression = vint(bytes, &read),
                      vint(bytes, &read) != nil,  // host OS
                      let nameSize = vint(bytes, &read),
                      nameSize >= 0, read + Int(nameSize) <= bytes.count
                else { break }
                let name = String(
                    bytes: bytes[read..<(read + Int(nameSize))], encoding: .utf8
                ) ?? ""

                let entryEncrypted = extraSize > 0 && hasEncryptionRecord(
                    bytes, from: Int(headerSize - extraSize)
                )
                if entryEncrypted { encrypted = true }

                // Only real files. A service header carries metadata, and
                // fileFlags bit 0 marks a directory.
                if type == 2, fileFlags & 0x0001 == 0, dataOffset + dataSize <= source.length {
                    guard entries.count < entryLimit else { throw RarError.tooManyEntries }
                    entries.append(
                        RarEntry(
                            path: name,
                            size: unpacked,
                            packedSize: dataSize,
                            dataOffset: dataOffset,
                            // CompressionInfo bits 7-9 hold the method; 0 is store.
                            isStored: (compression >> 7) & 0x07 == 0,
                            isSolid: compression & 0x40 != 0,
                            isEncrypted: entryEncrypted
                        )
                    )
                }
            default:
                break
            }

            guard nextOffset > offset else { break }  // never move backwards
            offset = nextOffset
        }
        return (entries, solidArchive, encrypted)
    }

    /// Whether a file header's extra area declares encryption (record type 1).
    /// Records are `size(vint) type(vint) payload`, with `size` covering the
    /// type and payload.
    private static func hasEncryptionRecord(_ bytes: [UInt8], from start: Int) -> Bool {
        var cursor = start
        guard cursor >= 0, cursor < bytes.count else { return false }
        while cursor < bytes.count {
            var probe = cursor
            guard let size = vint(bytes, &probe), size > 0 else { return false }
            var typeCursor = probe
            guard let type = vint(bytes, &typeCursor) else { return false }
            if type == 1 { return true }
            let next = probe + Int(size)
            guard next > cursor, next <= bytes.count else { return false }
            cursor = next
        }
        return false
    }

    /// RAR5's variable-length integer: seven bits per byte, low group first, high
    /// bit marks continuation. Capped at ten groups so a run of 0x80 bytes cannot
    /// spin, and rejected on overflow rather than wrapping.
    static func vint(_ bytes: [UInt8], _ cursor: inout Int) -> Int64? {
        var value: Int64 = 0
        var shift = 0
        var groups = 0
        while cursor < bytes.count, groups < 10 {
            let byte = bytes[cursor]
            cursor += 1
            groups += 1
            guard shift < 63 else { return nil }
            value |= Int64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value >= 0 ? value : nil }
            shift += 7
        }
        return nil
    }
}
