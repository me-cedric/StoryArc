import Foundation
import Testing

@testable import Formats

/// The 512 MB ceiling on one unpacked entry, which `SECURITY.md` publishes.
///
/// Android has enforced it since the decoder was written (`rar_decoder.c`,
/// `MAX_ENTRY_BYTES`); iOS reserved capacity against it and then let the loop
/// run. The published claim was therefore true on one platform only.
///
/// The archive is built here rather than committed to the shared corpus: a
/// fixture that *declares* six hundred megabytes is a header, not a comic, and
/// `packages/test-fixtures` describes publications the two platforms must agree
/// about. This one describes a refusal, and it is written by the same RAR5
/// writer `scripts/generate.py` uses so the bytes are the real format.
@Suite("RAR entry cap")
struct RarEntryCapTests {
    @Test("A declared unpacked size above the cap is refused before any data is read")
    func aDeclaredSizeAboveTheCapIsRefused() throws {
        let declared = 600 * 1024 * 1024
        let url = try writeArchive(
            name: "page-01.jpg", declaredSize: declared, payload: Data("far short of it".utf8)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        // Before the cap existed this failed too — as `.truncated`, after the
        // loop had drained whatever the archive chose to deliver. The point of
        // the cap is that the size is refused on the header, so a file that
        // *does* deliver its six hundred megabytes never allocates them.
        #expect(throws: RarDecoder.DecodeError.tooLarge(
            path: "page-01.jpg", declared: declared, cap: RarDecoder.maxEntryBytes
        )) {
            try RarDecoder.data(forEntryAt: "page-01.jpg", inArchiveAt: url)
        }
    }

    @Test("An entry that fits the cap still decodes, so the ceiling is a ceiling")
    func anEntryWithinTheCapStillDecodes() throws {
        let payload = Data("a page's worth of bytes".utf8)
        let url = try writeArchive(
            name: "page-01.jpg", declaredSize: payload.count, payload: payload
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try RarDecoder.data(forEntryAt: "page-01.jpg", inArchiveAt: url)
        #expect(read == payload)
    }

    @Test("The cap iOS enforces is the one Android enforces and SECURITY.md publishes")
    func theCapMatchesTheOtherPlatform() {
        // `rar_decoder.c`: `#define MAX_ENTRY_BYTES (512L * 1024L * 1024L)`.
        #expect(RarDecoder.maxEntryBytes == 512 * 1024 * 1024)
    }

    // MARK: - A RAR5 store-mode writer, ported from `scripts/generate.py`

    private func writeArchive(name: String, declaredSize: Int, payload: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cap-\(UUID().uuidString).cbr")
        try rar5(name: name, declaredSize: declaredSize, payload: payload).write(to: url)
        return url
    }

    /// A one-entry, store-mode RAR5 archive whose header may claim any size.
    private func rar5(name: String, declaredSize: Int, payload: Data) -> Data {
        var out = Data("Rar!\u{1a}\u{07}\u{01}\u{00}".utf8)
        out.append(block(type: 1, body: vint(0)))

        let encoded = Data(name.utf8)
        var body = Data()
        body.append(vint(0x0002 | 0x0004))  // mtime present, data CRC32 present
        body.append(vint(declaredSize))     // the untrusted field under test
        body.append(vint(0o100_644))        // attributes, Unix mode
        body.append(littleEndian(Self.mtime))
        body.append(littleEndian(crc32(payload)))
        body.append(vint(0x0000))           // RAR 5.0, method 0 (store), not solid
        body.append(vint(1))                // host OS: Unix
        body.append(vint(encoded.count))
        body.append(encoded)
        out.append(block(type: 2, body: body, data: payload))

        out.append(block(type: 5, body: vint(0)))  // end of archive
        return out
    }

    /// One RAR5 block. The CRC covers the header from its size field onwards.
    private func block(type: Int, body: Data, data: Data = Data()) -> Data {
        var tail = vint(type)
        tail.append(vint(data.isEmpty ? 0 : 0x0002))
        if !data.isEmpty { tail.append(vint(data.count)) }

        var sized = vint(tail.count + body.count)
        sized.append(tail)
        sized.append(body)

        var out = littleEndian(crc32(sized))
        out.append(sized)
        out.append(data)
        return out
    }

    /// RAR5 variable-length integer: seven bits per byte, low group first.
    private func vint(_ value: Int) -> Data {
        var remaining = value
        var out = Data()
        repeat {
            let group = UInt8(remaining & 0x7F)
            remaining >>= 7
            out.append(remaining != 0 ? group | 0x80 : group)
        } while remaining != 0
        return out
    }

    private func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// The same CRC-32 zlib computes, table-free because three calls do not need a table.
    private func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// 2026-01-01T00:00:00Z, the instant `scripts/generate.py` fixes so bytes never drift.
    private static let mtime: UInt32 = 1_767_225_600
}
