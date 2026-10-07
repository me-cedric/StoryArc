import Foundation

extension AudioTagIdentifiers {
    /// The `TXXX` frames of an ID3v2.2, 2.3 or 2.4 tag.
    static func id3(_ source: some RandomAccessSource) async throws -> [Tag] {
        let header = [UInt8](try await source.readExactly(offset: 0, count: 10))
        let major = Int(header[3])
        let size = syncsafe(header, at: 6)
        guard (2...4).contains(major), size <= maxTagBytes else { return [] }
        let available = max(0, min(Int64(size), source.length - 10))
        let tag = [UInt8](try await source.read(offset: 10, count: Int(available)))
        var at = 0
        // An extended header sits before the frames. 2.4 counts itself in its size; 2.3 does not.
        if major >= 3, header[5] & 0x40 != 0, tag.count >= 4 {
            at = major == 4 ? syncsafe(tag, at: 0) : 4 + beInt(tag, at: 0)
        }
        let idLength = major == 2 ? 3 : 4
        let frameHeader = major == 2 ? 6 : 10
        var found: [Tag] = []
        while at + frameHeader <= tag.count, tag[at] != 0 {
            let id = String(bytes: tag[at..<at + idLength], encoding: .isoLatin1) ?? ""
            let length = frameLength(tag, at: at, major: major)
            let body = at + frameHeader
            guard body + length <= tag.count else { break }
            if id == "TXXX" || id == "TXX", let entry = txxx(tag[body..<body + length]) {
                found.append(entry)
            }
            at = body + length
        }
        return found
    }

    private static func frameLength(_ tag: [UInt8], at index: Int, major: Int) -> Int {
        switch major {
        case 2: Int(tag[index + 3]) << 16 | Int(tag[index + 4]) << 8 | Int(tag[index + 5])
        case 4: syncsafe(tag, at: index + 4)
        default: beInt(tag, at: index + 4)
        }
    }

    /// A user text frame: an encoding byte, a description, a terminator, then the value.
    private static func txxx(_ frame: ArraySlice<UInt8>) -> Tag? {
        guard frame.count >= 2, let first = frame.first else { return nil }
        let encoding: String.Encoding = switch first {
        case 1: .utf16
        case 2: .utf16BigEndian
        case 3: .utf8
        default: .isoLatin1
        }
        let wide = first == 1 || first == 2
        let body = frame.dropFirst()
        guard let end = terminator(body, wide: wide) else { return nil }
        let valueStart = min(end + (wide ? 2 : 1), body.endIndex)
        guard let name = text(body[body.startIndex..<end], encoding),
              let value = text(body[valueStart...], encoding)
        else { return nil }
        return (name, value)
    }

    private static func terminator(_ bytes: ArraySlice<UInt8>, wide: Bool) -> Int? {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if !wide, bytes[index] == 0 { return index }
            if wide, index + 1 < bytes.endIndex, bytes[index] == 0, bytes[index + 1] == 0 {
                return index
            }
            index += wide ? 2 : 1
        }
        return nil
    }
}
