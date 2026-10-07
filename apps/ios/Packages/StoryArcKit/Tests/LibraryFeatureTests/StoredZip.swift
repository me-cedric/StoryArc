import Foundation

/// A ZIP archive of stored entries, built in memory, for tests that need a small container.
enum StoredZip {
    static func build(_ entries: [(name: String, data: Data)]) -> Data {
        var body = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(body.count)
            body.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
            body.append(le16(20)); body.append(le16(0)); body.append(le16(0))
            body.append(le16(0)); body.append(le16(0x21))
            body.append(le32(crc)); body.append(le32(UInt32(entry.data.count)))
            body.append(le32(UInt32(entry.data.count)))
            body.append(le16(UInt16(name.count))); body.append(le16(0))
            body.append(name); body.append(entry.data)

            directory.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
            directory.append(le16(20)); directory.append(le16(20)); directory.append(le16(0))
            directory.append(le16(0)); directory.append(le16(0)); directory.append(le16(0x21))
            directory.append(le32(crc)); directory.append(le32(UInt32(entry.data.count)))
            directory.append(le32(UInt32(entry.data.count)))
            directory.append(le16(UInt16(name.count)))
            directory.append(Data(count: 12))
            directory.append(le32(offset))
            directory.append(name)
        }
        var archive = body
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        archive.append(le16(0)); archive.append(le16(0))
        archive.append(le16(UInt16(entries.count))); archive.append(le16(UInt16(entries.count)))
        archive.append(le32(UInt32(directory.count))); archive.append(le32(directoryOffset))
        archive.append(le16(0))
        return archive
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xff), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xff) })
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
