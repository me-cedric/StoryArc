import Foundation

extension AudioTagIdentifiers {
    private struct Box {
        let type: String
        let from: Int
        let to: Int
    }

    /// The custom tags of an MP4 file: iTunes freeform atoms and QuickTime keyed items.
    static func mp4(_ source: some RandomAccessSource) async throws -> [Tag] {
        var offset: Int64 = 0
        while offset + 8 <= source.length {
            let header = [UInt8](try await source.readExactly(offset: offset, count: 8))
            var size = Int64(beInt(header, at: 0))
            var headerSize: Int64 = 8
            if size == 1 {
                let wide = [UInt8](try await source.readExactly(offset: offset + 8, count: 8))
                let high = beInt(wide, at: 0)
                guard high < 0x8000_0000 else { return [] }
                size = Int64(high) << 32 | Int64(beInt(wide, at: 4))
                headerSize = 16
            } else if size == 0 {
                size = source.length - offset
            }
            guard size >= headerSize, size <= source.length - offset else { return [] }
            if String(bytes: header[4..<8], encoding: .isoLatin1) == "moov" {
                let payload = size - headerSize
                guard payload <= maxTagBytes else { return [] }
                let moov = [UInt8](try await source.read(offset: offset + headerSize, count: Int(payload)))
                return items(inMoov: moov)
            }
            offset += size
        }
        return []
    }

    private static func boxes(_ bytes: [UInt8], _ from: Int, _ to: Int) -> [Box] {
        var found: [Box] = []
        var at = from
        while at + 8 <= to {
            let size = beInt(bytes, at: at)
            guard size >= 8, at + size <= to else { break }
            let type = String(bytes: bytes[at + 4..<at + 8], encoding: .isoLatin1) ?? ""
            found.append(Box(type: type, from: at + 8, to: at + size))
            at += size
        }
        return found
    }

    private static func items(inMoov moov: [UInt8]) -> [Tag] {
        guard let udta = boxes(moov, 0, moov.count).first(where: { $0.type == "udta" }),
              let meta = boxes(moov, udta.from, udta.to).first(where: { $0.type == "meta" })
        else { return [] }
        // `meta` is a full box: four bytes of version and flags come before its children.
        let inner = boxes(moov, meta.from + 4, meta.to)
        guard let list = inner.first(where: { $0.type == "ilst" }) else { return [] }
        let keys = inner.first { $0.type == "keys" }.map { mdtaKeys(moov, $0) } ?? []
        return boxes(moov, list.from, list.to).compactMap { item in
            let children = boxes(moov, item.from, item.to)
            guard let data = children.first(where: { $0.type == "data" }),
                  data.to - data.from >= 8
            else { return nil }
            // iTunes names a custom tag in a `name` atom; the QuickTime form numbers the item
            // and lists the names once in `keys`.
            let named = item.type == "----" ? children.first { $0.type == "name" } : nil
            let name: String?
            if let named, named.to - named.from >= 4 {
                name = String(bytes: moov[named.from + 4..<named.to], encoding: .utf8)
            } else {
                let index = beInt(moov, at: item.from - 4) - 1
                name = keys.indices.contains(index) ? keys[index] : nil
            }
            guard let name,
                  let value = String(bytes: moov[data.from + 8..<data.to], encoding: .utf8)
            else { return nil }
            return (name, value)
        }
    }

    /// The names a QuickTime `keys` atom lists in order: each is a size, a namespace, a name.
    private static func mdtaKeys(_ moov: [UInt8], _ keys: Box) -> [String] {
        var names: [String] = []
        var at = keys.from + 8
        while at + 8 <= keys.to {
            let size = beInt(moov, at: at)
            guard size >= 8, at + size <= keys.to else { break }
            names.append(String(bytes: moov[at + 8..<at + size], encoding: .utf8) ?? "")
            at += size
        }
        return names
    }
}
