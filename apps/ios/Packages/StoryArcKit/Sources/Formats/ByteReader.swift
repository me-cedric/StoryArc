internal import Foundation

/// Little-endian reads over a `Data` buffer, bounds-checked.
///
/// Every ZIP structure is little-endian. Bounds checks are not optional here:
/// this parser runs on untrusted input, and `SECURITY.md` names archive parsing
/// as the largest attack surface in the app. No length read out of a file is
/// ever used to allocate without being checked against the buffer first.
struct ByteReader {
    private let bytes: Data
    private(set) var cursor: Int

    init(_ data: Data, at offset: Int = 0) {
        self.bytes = data
        self.cursor = offset
    }

    var remaining: Int { bytes.count - cursor }

    mutating func seek(to offset: Int) throws {
        guard offset >= 0, offset <= bytes.count else { throw ZipError.malformed("seek out of range") }
        cursor = offset
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, cursor + count <= bytes.count else {
            throw ZipError.malformed("skip past end")
        }
        cursor += count
    }

    mutating func uint16() throws -> UInt16 {
        try UInt16(fixedWidth: read(2))
    }

    mutating func uint32() throws -> UInt32 {
        try UInt32(fixedWidth: read(4))
    }

    mutating func uint64() throws -> UInt64 {
        try UInt64(fixedWidth: read(8))
    }

    mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, cursor + count <= bytes.count else {
            throw ZipError.malformed("read past end")
        }
        let start = bytes.startIndex + cursor
        let slice = bytes[start..<(start + count)]
        cursor += count
        return Data(slice)
    }

    /// An entry name. ZIP stores UTF-8 when general-purpose bit 11 is set, and
    /// an unspecified code page otherwise. Falling back to ISO-8859-1 keeps
    /// every byte round-trippable rather than losing a name to a decode failure.
    mutating func string(_ count: Int, isUTF8: Bool) throws -> String {
        let raw = try read(count)
        if isUTF8, let text = String(data: raw, encoding: .utf8) { return text }
        return String(data: raw, encoding: .isoLatin1) ?? ""
    }
}

private extension FixedWidthInteger {
    init(fixedWidth data: Data) {
        var value: Self = 0
        for (index, byte) in data.enumerated() {
            value |= Self(byte) << (8 * index)
        }
        self = value
    }
}
