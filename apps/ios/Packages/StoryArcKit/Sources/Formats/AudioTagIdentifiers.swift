public import Foundation

public import StoryArcCore

/// The identifiers an audio file's tags carry, for the cover lookup (`cover-art`, task 6.1).
///
/// Read here rather than through AVFoundation: it names an ID3 `TXXX` frame by its
/// description but gives an MP4 freeform atom no name at all, and an Audible ASIN lives in
/// one. The three containers are read directly: ID3v2 `TXXX` frames (MP3), MP4 freeform
/// atoms (M4B, M4A) and Vorbis comments (FLAC, Ogg). Android's `AudioTagIdentifiers` reads
/// the same bytes the same way.
///
/// An Audible ASIN wins over a MusicBrainz release group where a file carries both, because
/// it names the book and the release group names the album it was ripped from.
public enum AudioTagIdentifiers {
    typealias Tag = (name: String, value: String)

    static let maxTagBytes = 16 * 1024 * 1024
    private static let oggHeadBytes = 256 * 1024
    private static let asinNames: Set<String> = ["asin", "audibleasin", "cdek"]
    private static let releaseGroupName = "musicbrainzreleasegroupid"

    /// The identifier a file's tags name, or nil. Reads only the tag area, never the audio.
    public static func identifier(in source: some RandomAccessSource) async -> CoverIdentifier? {
        guard let head = try? await source.read(offset: 0, count: 12) else { return nil }
        let bytes = [UInt8](head)
        let tags: [Tag]
        if bytes.starts(with: Array("ID3".utf8)) {
            tags = (try? await id3(source)) ?? []
        } else if bytes.count >= 8, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            tags = (try? await mp4(source)) ?? []
        } else if bytes.starts(with: Array("fLaC".utf8)) {
            tags = (try? await flac(source)) ?? []
        } else if bytes.starts(with: Array("OggS".utf8)) {
            tags = (try? await ogg(source)) ?? []
        } else {
            tags = []
        }
        return identifier(fromTags: tags)
    }

    /// Tag name and value pairs to an identifier. Names compare without case or separators.
    static func identifier(fromTags tags: [Tag]) -> CoverIdentifier? {
        // A writer may end a text frame with a NUL, and a NUL is not part of an identifier.
        let padding = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))
        let named = tags.map { (normalised($0.name), $0.value.trimmingCharacters(in: padding)) }
        if let asin = named.first(where: { asinNames.contains($0.0) })
            .flatMap({ CoverIdentifier.asin(reading: $0.1) }) {
            return asin
        }
        return named.first { $0.0 == releaseGroupName }
            .flatMap { CoverIdentifier.musicBrainz(reading: $0.1) }
    }

    private static func normalised(_ name: String) -> String {
        let last = name.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init)
        return (last ?? name).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Byte helpers

    static func beInt(_ bytes: [UInt8], at index: Int) -> Int {
        (0..<4).reduce(0) { ($0 << 8) | Int(bytes[index + $1]) }
    }

    static func leInt(_ bytes: [UInt8], at index: Int) -> Int {
        (0..<4).reduce(0) { $0 | (Int(bytes[index + $1]) << (8 * $1)) }
    }

    static func syncsafe(_ bytes: [UInt8], at index: Int) -> Int {
        (0..<4).reduce(0) { ($0 << 7) | Int(bytes[index + $1] & 0x7f) }
    }

    static func text(_ bytes: ArraySlice<UInt8>, _ encoding: String.Encoding) -> String? {
        String(bytes: bytes, encoding: encoding)
    }

    // MARK: - FLAC and Ogg

    private static func flac(_ source: some RandomAccessSource) async throws -> [Tag] {
        var offset: Int64 = 4
        while offset + 4 <= source.length {
            let header = [UInt8](try await source.readExactly(offset: offset, count: 4))
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if header[0] & 0x7f == 4 {
                guard length <= maxTagBytes else { return [] }
                return vorbisComments([UInt8](try await source.read(offset: offset + 4, count: length)))
            }
            if header[0] & 0x80 != 0 { break }
            offset += 4 + Int64(length)
        }
        return []
    }

    private static func vorbisComments(_ block: [UInt8]) -> [Tag] {
        guard block.count >= 8 else { return [] }
        var at = 4 + leInt(block, at: 0)
        guard at + 4 <= block.count else { return [] }
        let count = leInt(block, at: at)
        at += 4
        var found: [Tag] = []
        for _ in 0..<count {
            guard at + 4 <= block.count else { break }
            let length = leInt(block, at: at)
            at += 4
            guard at + length <= block.count else { break }
            let entry = text(block[at..<at + length], .utf8) ?? ""
            at += length
            if let equals = entry.firstIndex(of: "="), equals != entry.startIndex {
                found.append((String(entry[..<equals]), String(entry[entry.index(after: equals)...])))
            }
        }
        return found
    }

    private static func ogg(_ source: some RandomAccessSource) async throws -> [Tag] {
        let count = Int(min(source.length, Int64(oggHeadBytes)))
        let head = text(ArraySlice([UInt8](try await source.read(offset: 0, count: count))), .isoLatin1) ?? ""
        let pattern = "(MUSICBRAINZ_RELEASEGROUPID|AUDIBLE_ASIN|ASIN)=([\\x21-\\x7e]{1,64})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let whole = NSRange(head.startIndex..., in: head)
        return regex.matches(in: head, range: whole).compactMap { match in
            guard let name = Range(match.range(at: 1), in: head),
                  let value = Range(match.range(at: 2), in: head)
            else { return nil }
            return (String(head[name]), String(head[value]))
        }
    }
}
