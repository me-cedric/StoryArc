import Foundation

@testable import Formats

/// Builders for the streaming tests: a fixture's bytes, and the same bytes with an entry
/// renamed so the comic layer lists it as a page.
///
/// The corpus's compressed RARs come from libarchive's own suite, where the entries are
/// `.bin` and `.txt` files. A rename changes the name and the header CRC that covers it,
/// and nothing else, so the packed bytes stay exactly as a real compressor wrote them.
enum RarStreamingFixtures {
    static func load(_ name: String) throws -> Data {
        try Data(contentsOf: FixtureCorpus.url("comics/\(name)"))
    }

    /// `bytes` with each entry named by a key renamed to its value, of the same length.
    static func renamed(_ bytes: Data, _ names: [String: String]) async throws -> Data {
        let reader = try await RarReader(source: DataSource(bytes))
        var out = [UInt8](bytes)
        for entry in reader.entries {
            guard let newName = names[entry.path] else { continue }
            let old = [UInt8](entry.path.utf8)
            let new = [UInt8](newName.utf8)
            precondition(old.count == new.count, "a rename must keep the header length")
            let header = Int(entry.headerOffset)..<Int(entry.dataOffset)
            let at = try firstIndex(of: old, in: out, within: header)
            out.replaceSubrange(at..<(at + new.count), with: new)
            rewriteCrc(&out, header: header, generation: reader.generation)
        }
        return Data(out)
    }

    /// libarchive's own generator for `test.bin`: each little-endian 32-bit word at index
    /// `i` is `max(0, k*k - 3*k + 1)` for `k = i + 1`.
    static func expectedBinContent(byteCount: Int) -> Data {
        var out = Data(capacity: byteCount)
        for index in 0..<(byteCount / 4) {
            let step = index + 1
            let value = max(0, step * step - 3 * step + 1)
            out.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian) { Array($0) })
        }
        return out
    }

    private struct NameNotFound: Error {}

    private static func firstIndex(
        of needle: [UInt8], in bytes: [UInt8], within range: Range<Int>
    ) throws -> Int {
        for start in range.lowerBound...(range.upperBound - needle.count)
        where Array(bytes[start..<(start + needle.count)]) == needle {
            return start
        }
        throw NameNotFound()
    }

    /// RAR5 keeps a CRC32 of the header from its size field on. RAR4 keeps the low 16 bits
    /// of a CRC32 of the header from its type byte on.
    private static func rewriteCrc(_ bytes: inout [UInt8], header: Range<Int>, generation: RarGeneration) {
        let crcWidth = generation == .rar5 ? 4 : 2
        let crc = crc32(bytes[(header.lowerBound + crcWidth)..<header.upperBound])
        for index in 0..<crcWidth {
            bytes[header.lowerBound + index] = UInt8(truncatingIfNeeded: crc >> (8 * index))
        }
    }

    private static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
