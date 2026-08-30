import Foundation
import Testing

@testable import Formats

/// Archives whose header fields are chosen to overflow `Int64`.
///
/// Not in the shared corpus: these are a handful of bytes each, and a fixture generator
/// that writes deliberately impossible offsets would have to be taught to lie. Android's
/// `ArchiveOverflowTest` asserts the same four cases in the same order — there the
/// arithmetic wraps and the wrapped value is refused downstream, here it would trap the
/// process, and both ends must end up throwing.
@Suite("Archives with overflowing header fields")
struct ArchiveOverflowTests {
    @Test("A zip64 locator pointing near Int64.max is refused, not added to")
    func zip64LocatorOffsetOverflows() async throws {
        // `recordOffset + 56` is the guard's own arithmetic. At this offset the addition
        // overflows before the comparison runs, which on Swift is a process abort.
        var bytes = Crafted(Data(repeating: 0, count: 64))
        bytes.zip64Locator(recordOffset: 0x7FFF_FFFF_FFFF_FFC8)
        bytes.endOfCentralDirectory(entryCount: 0, size: 0, offset: 0)

        await #expect(throws: ZipError.self) {
            _ = try await ZipReader(source: DataSource(bytes.data))
        }
    }

    @Test("A zip64 record whose directory size and offset sum past Int64.max is refused")
    func zip64DirectorySpanOverflows() async throws {
        // Both values are positive and each one on its own passes a `>= 0` check. Their
        // sum is what leaves Int64, and it is the sum the bounds guard needs.
        var bytes = Crafted()
        bytes.zip64EndOfCentralDirectory(
            size: 0x4000_0000_0000_0000,
            offset: 0x4000_0000_0000_0000
        )
        bytes.zip64Locator(recordOffset: 0)
        bytes.endOfCentralDirectory(entryCount: 0, size: 0, offset: 0)

        await #expect(throws: ZipError.self) {
            _ = try await ZipReader(source: DataSource(bytes.data))
        }
    }

    @Test("A zip64 extra field cannot give an entry a negative local header offset")
    func zip64EntryOffsetIsNegative() async throws {
        // `source.length - localHeaderOffset` is the subtraction that reads the local
        // header. With Int64.min it overflows, so the offset is rejected where it is
        // parsed instead — an entry outside the file is a lie, not damage.
        var bytes = Crafted()
        bytes.localHeader(name: "page1.png")
        let directoryOffset = bytes.count
        bytes.centralDirectoryEntry(name: "page1.png", zip64LocalOffset: Int64.min)
        let directorySize = bytes.count - directoryOffset
        bytes.endOfCentralDirectory(entryCount: 1, size: directorySize, offset: directoryOffset)

        await #expect(throws: (any Error).self) {
            let zip = try await ZipReader(source: DataSource(bytes.data))
            let entry = try #require(zip.entries.first)
            _ = try await zip.data(for: entry)
        }
    }

    @Test("A GNU base-256 TAR size near Int64.max does not overflow the block padding")
    func tarBase256SizeOverflows() async throws {
        // `(size + 511) / 512 * 512` runs before the size is checked against the file.
        // A size of Int64.max - 256 makes that first addition the trap.
        var header = [UInt8](repeating: 0, count: 512)
        header.replaceSubrange(0..<9, with: Array("page1.png".utf8))
        header.replaceSubrange(257..<262, with: Array("ustar".utf8))
        header[156] = 0x30  // regular file
        // High bit set marks base-256; the remaining bytes are the integer, big-endian.
        header.replaceSubrange(124..<136, with: [
            0x80, 0x00, 0x00, 0x00,
            0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE, 0xFF,
        ])
        Crafted.writeTarChecksum(into: &header)

        // Surviving is the assertion: a reader that traps never reaches the expectation.
        let reader = try await TarReader(source: DataSource(Data(header)))
        #expect(reader.entries.isEmpty, "an entry claiming Int64.max bytes is not readable")
    }
}

/// Bytes assembled by hand, because no archive writer produces these.
private struct Crafted {
    private(set) var data: Data

    var count: Int64 { Int64(data.count) }

    init(_ data: Data = Data()) { self.data = data }

    mutating func uint16(_ value: UInt16) {
        data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func uint32(_ value: UInt32) {
        data.append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }

    mutating func uint64(_ value: UInt64) {
        data.append(contentsOf: (0..<8).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }

    mutating func localHeader(name: String) {
        uint32(0x0403_4B50)
        uint16(20)                    // version needed
        uint16(0)                     // flags
        uint16(0)                     // method: stored
        uint32(0)                     // time and date
        uint32(0)                     // crc
        uint32(0)                     // compressed size
        uint32(0)                     // uncompressed size
        uint16(UInt16(name.utf8.count))
        uint16(0)                     // extra length
        data.append(contentsOf: Array(name.utf8))
    }

    /// A central directory entry whose local header offset is the zip64 sentinel, with
    /// the real value carried in the extra field where nothing range-checked it.
    mutating func centralDirectoryEntry(name: String, zip64LocalOffset: Int64) {
        uint32(0x0201_4B50)
        uint16(20)                    // version made by
        uint16(20)                    // version needed
        uint16(0)                     // flags
        uint16(0)                     // method: stored
        uint32(0)                     // time and date
        uint32(0)                     // crc
        uint32(0)                     // compressed size
        uint32(0)                     // uncompressed size
        uint16(UInt16(name.utf8.count))
        uint16(12)                    // extra length: one zip64 block
        uint16(0)                     // comment length
        uint16(0)                     // disk start
        uint16(0)                     // internal attributes
        uint32(0)                     // external attributes
        uint32(0xFFFF_FFFF)           // local offset: "read the zip64 extra field"
        data.append(contentsOf: Array(name.utf8))
        uint16(0x0001)                // zip64 extended information
        uint16(8)
        uint64(UInt64(bitPattern: zip64LocalOffset))
    }

    mutating func zip64EndOfCentralDirectory(size: Int64, offset: Int64) {
        uint32(0x0606_4B50)
        uint64(44)                    // record size
        uint16(45)                    // version made by
        uint16(45)                    // version needed
        uint32(0)                     // this disk
        uint32(0)                     // disk with the central directory
        uint64(1)                     // entries on this disk
        uint64(1)                     // entries in total
        uint64(UInt64(bitPattern: size))
        uint64(UInt64(bitPattern: offset))
    }

    mutating func zip64Locator(recordOffset: Int64) {
        uint32(0x0706_4B50)
        uint32(0)                     // disk holding the zip64 EOCD
        uint64(UInt64(bitPattern: recordOffset))
        uint32(1)                     // total disks
    }

    mutating func endOfCentralDirectory(entryCount: UInt16, size: Int64, offset: Int64) {
        uint32(0x0605_4B50)
        uint16(0)                     // this disk
        uint16(0)                     // disk with the central directory
        uint16(entryCount)            // entries on this disk
        uint16(entryCount)            // entries in total
        uint32(UInt32(truncatingIfNeeded: size))
        uint32(UInt32(truncatingIfNeeded: offset))
        uint16(0)                     // comment length
    }

    /// The checksum a real TAR writer would have written for this header.
    static func writeTarChecksum(into header: inout [UInt8]) {
        for index in 148..<156 { header[index] = 0x20 }
        let sum = header.reduce(0) { $0 + Int($1) }
        let field = Array(String(format: "%06o", sum).utf8) + [0x00, 0x20]
        header.replaceSubrange(148..<156, with: field)
    }
}
