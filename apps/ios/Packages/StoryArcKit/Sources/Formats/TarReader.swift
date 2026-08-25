public import Foundation

/// One regular file inside a TAR archive.
public struct TarEntry: Sendable, Equatable {
    public let path: String
    public let size: Int64
    /// Where the file's bytes start. TAR stores data uncompressed and contiguous,
    /// so this offset plus `size` is the whole read — no decode step at all.
    public let dataOffset: Int64
}

public enum TarError: Error, Equatable {
    case malformed(String)
    /// No `ustar` magic and no parsable header. The file is not a TAR.
    case notTar
}

/// A TAR reader, written here rather than delegated to libarchive.
///
/// TAR is 512-byte blocks with fixed-offset ASCII fields: there is no
/// compression, no central directory and no bit-packing. Reading it needs no C
/// library, which is the same reasoning ADR-0008 applies to ZIP — and it means
/// CBT ships without waiting on the libarchive vendoring question.
///
/// Every read goes through `RandomAccessSource`, so indexing a CBT on an SMB
/// share fetches one 512-byte header per entry rather than the whole file.
///
/// This parser runs on untrusted input. `SECURITY.md` names archive parsing as
/// the largest attack surface in the app, so no length taken from a header is
/// used before it is checked against the source, and every header's checksum is
/// verified.
public struct TarReader: Sendable {
    /// Regular files only, in archive order. Directories, symlinks and metadata
    /// blocks are consumed and dropped.
    public let entries: [TarEntry]

    private let source: any RandomAccessSource

    private static let blockSize = 512
    /// `ustar` sits at offset 257, which is why format sniffing has to read
    /// further into a TAR than into any other container.
    static let magicOffset = 257

    // A TAR header is 512 bytes of fixed fields with a branch per type flag, GNU
    // long name and pax record included. The branches are the format.
    // swiftlint:disable:next cyclomatic_complexity
    public init(source: any RandomAccessSource) async throws {
        self.source = source

        var found: [TarEntry] = []
        var offset: Int64 = 0
        /// Set by a GNU `L` block or a pax `path=` record, and consumed by the
        /// next real entry.
        var pendingLongName: String?
        var sawAnyHeader = false

        while offset + Int64(Self.blockSize) <= source.length {
            let block = try await source.readExactly(offset: offset, count: Self.blockSize)
            offset += Int64(Self.blockSize)

            // Two consecutive zero blocks end an archive, but one is enough to
            // stop: there is nothing after it a reader could use.
            if block.allSatisfy({ $0 == 0 }) { break }

            guard Self.checksumMatches(block) else {
                // A bad checksum on the very first block means this was never a
                // TAR. Later on it means the archive is damaged, and
                // `publication-formats` requires returning what was readable.
                if !sawAnyHeader { throw TarError.notTar }
                break
            }
            sawAnyHeader = true

            let size = try Self.size(of: block)
            let dataOffset = offset
            // Entry data is padded to a whole number of blocks.
            offset += (size + Int64(Self.blockSize) - 1) / Int64(Self.blockSize) * Int64(Self.blockSize)

            guard size >= 0, dataOffset + size <= source.length else {
                // The header claims more bytes than the file holds. Stop rather
                // than trusting the next offset, which is now meaningless.
                break
            }

            switch Self.typeFlag(of: block) {
            case 0x4C:  // 'L' — GNU long name; this block's data names the next entry.
                pendingLongName = Self.trimmedString(
                    try await source.readExactly(offset: dataOffset, count: Int(min(size, 8192)))
                )
            case 0x78, 0x67:  // 'x', 'g' — pax extended header.
                let raw = try await source.readExactly(offset: dataOffset, count: Int(min(size, 8192)))
                pendingLongName = Self.paxPath(in: raw) ?? pendingLongName
            case 0x30, 0x00:  // '0' or NUL — a regular file.
                let path = pendingLongName ?? Self.path(of: block)
                pendingLongName = nil
                if !path.isEmpty, !path.hasSuffix("/") {
                    found.append(TarEntry(path: path, size: size, dataOffset: dataOffset))
                }
            default:
                // Directories, symlinks, devices, FIFOs. Not pages.
                pendingLongName = nil
            }
        }

        guard sawAnyHeader else { throw TarError.notTar }
        self.entries = found
    }

    /// A whole entry. No decompression: TAR stores bytes verbatim.
    public func data(for entry: TarEntry) async throws -> Data {
        guard entry.size >= 0, entry.dataOffset >= 0,
              entry.dataOffset + entry.size <= source.length
        else { throw TarError.malformed("entry lies outside the source") }
        return try await source.readExactly(offset: entry.dataOffset, count: Int(entry.size))
    }

    // MARK: - Header fields

    /// The header checksum, treating its own eight bytes as spaces.
    ///
    /// Historic writers disagreed on whether the bytes are signed, so both sums
    /// are accepted. This is the only integrity check TAR offers, and it is what
    /// stops a random 512 bytes from being read as an entry.
    private static func checksumMatches(_ block: Data) -> Bool {
        let bytes = Array(block)
        guard bytes.count == blockSize else { return false }
        guard let declared = try? octal(bytes[148..<156]) else { return false }
        var unsigned = 0
        var signed = 0
        for (index, byte) in bytes.enumerated() {
            let value = (148..<156).contains(index) ? 0x20 : Int(byte)
            unsigned += value
            signed += (148..<156).contains(index) ? 0x20 : Int(Int8(bitPattern: byte))
        }
        return declared == Int64(unsigned) || declared == Int64(signed)
    }

    private static func typeFlag(of block: Data) -> UInt8 {
        Array(block)[156]
    }

    /// USTAR splits long paths across a 155-byte prefix and a 100-byte name.
    private static func path(of block: Data) -> String {
        let bytes = Array(block)
        let name = trimmedString(Data(bytes[0..<100]))
        let isUstar = Array(bytes[257..<262]) == Array("ustar".utf8)
        guard isUstar else { return name }
        let prefix = trimmedString(Data(bytes[345..<500]))
        return prefix.isEmpty ? name : "\(prefix)/\(name)"
    }

    private static func size(of block: Data) throws -> Int64 {
        let field = Array(block)[124..<136]
        // GNU base-256: the high bit of the first byte marks a big-endian
        // integer instead of ASCII octal, for sizes that will not fit in 11
        // octal digits.
        if let first = field.first, first & 0x80 != 0 {
            var value: Int64 = Int64(first & 0x7F)
            for byte in field.dropFirst() {
                guard value < Int64.max >> 8 else { throw TarError.malformed("size overflows") }
                value = value << 8 | Int64(byte)
            }
            return value
        }
        return try octal(field)
    }

    private static func octal(_ bytes: ArraySlice<UInt8>) throws -> Int64 {
        var value: Int64 = 0
        var sawDigit = false
        for byte in bytes {
            if byte == 0 || byte == 0x20 {
                // Trailing NUL or space terminates the field; leading ones are padding.
                if sawDigit { break } else { continue }
            }
            guard byte >= 0x30, byte <= 0x37 else { throw TarError.malformed("not an octal field") }
            guard value < Int64.max >> 3 else { throw TarError.malformed("octal field overflows") }
            value = value << 3 | Int64(byte - 0x30)
            sawDigit = true
        }
        guard sawDigit else { return 0 }
        return value
    }

    /// A NUL-terminated fixed-width field. UTF-8 where possible, ISO-8859-1
    /// otherwise, so no byte sequence costs us an entry name.
    private static func trimmedString(_ data: Data) -> String {
        let bytes = Array(data.prefix(while: { $0 != 0 }))
        return String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
    }

    /// The `path=` record from a pax extended header. Records are
    /// `<length> <key>=<value>\n`, with the length counting the whole record.
    private static func paxPath(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var rest = Substring(text)
        while let space = rest.firstIndex(of: " ") {
            guard let declared = Int(rest[rest.startIndex..<space]), declared > 0,
                  declared <= rest.count
            else { return nil }
            let record = rest.prefix(declared)
            rest = rest.dropFirst(declared)
            let body = record[record.index(after: space)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            if body.hasPrefix("path=") { return String(body.dropFirst("path=".count)) }
        }
        return nil
    }
}
