import Foundation
import Testing

@testable import Formats
import StoryArcCore

/// The identifiers the cover lookup reads out of audio tags, container by container.
///
/// Task 6.1 of `cover-for-every-publication`. Each container is built here byte by byte,
/// because the claim is about where in the container the reader looks. Android's
/// `AudioTagIdentifiersTest` builds the same bytes and asserts the same answers.
@Suite("Audio tag identifiers")
struct AudioTagIdentifiersTests {
    private let releaseGroup = "6a6bd3a5-0b7c-4a37-9f2b-6b5d6e2d9e11"
    private let asin = "B08G9PRS1K"

    private func read(_ bytes: [UInt8]) async -> CoverIdentifier? {
        await AudioTagIdentifiers.identifier(in: DataSource(Data(bytes)))
    }

    // MARK: ID3

    @Test("An ID3v2.3 TXXX frame names the release group")
    func id3v23() async {
        let tag = id3(3, frame("TSSE", 3, [0] + Array("Lavf".utf8)),
                      frame("TXXX", 3, txxx(0, "MusicBrainz Release Group Id", releaseGroup)))

        #expect(await read(tag) == .musicBrainzReleaseGroup(releaseGroup))
    }

    @Test("An ID3v2.4 frame with a UTF-16 description and a syncsafe size is read")
    func id3v24() async {
        let tag = id3(4, frame("TXXX", 4, txxx(1, "ASIN", asin)))

        #expect(await read(tag) == .audibleASIN(asin))
    }

    @Test("A text frame that ends in a NUL still names the identifier")
    func id3NulTerminatedValue() async {
        // ffmpeg writes ID3v2.4 text frames this way, and a UUID with a NUL on it is no UUID.
        let tag = id3(4, frame("TXXX", 4, txxx(3, "MusicBrainz Release Group Id", releaseGroup + "\0")))

        #expect(await read(tag) == .musicBrainzReleaseGroup(releaseGroup))
    }

    @Test("An ID3 tag that names neither identifier reads none")
    func id3Neither() async {
        let tag = id3(3, frame("TXXX", 3, txxx(0, "ENCODEDBY", "someone")))

        #expect(await read(tag) == nil)
    }

    // MARK: MP4

    @Test("An iTunes freeform atom names the ASIN")
    func freeform() async {
        #expect(await read(mp4(freeform("com.apple.iTunes", "ASIN", asin))) == .audibleASIN(asin))
    }

    @Test("A QuickTime keys atom names the release group by the item's index")
    func quickTimeKeys() async {
        let file = mp4Keys(["title", "MusicBrainz Release Group Id"], [2: releaseGroup])

        #expect(await read(file) == .musicBrainzReleaseGroup(releaseGroup))
    }

    @Test("A moov atom that comes after a large mdat is still found")
    func moovAfterMdat() async {
        let file = mp4(freeform("com.apple.iTunes", "ASIN", asin), mdatBytes: 200_000)

        #expect(await read(file) == .audibleASIN(asin))
    }

    // MARK: FLAC and Ogg

    @Test("A FLAC Vorbis comment block after other blocks names the release group")
    func flac() async {
        let comment = vorbis("MUSICBRAINZ_RELEASEGROUPID=\(releaseGroup)", "ALBUM=x")
        let file = Array("fLaC".utf8) + block(0, [UInt8](repeating: 0, count: 34), last: false)
            + block(4, comment, last: true)

        #expect(await read(file) == .musicBrainzReleaseGroup(releaseGroup))
    }

    @Test("An Ogg comment packet names the ASIN")
    func ogg() async {
        let file = Array("OggS".utf8) + [UInt8](repeating: 0, count: 40) + [3] + Array("vorbis".utf8)
            + vorbis("ASIN=\(asin)")

        #expect(await read(file) == .audibleASIN(asin))
    }

    // MARK: Precedence and refusal

    @Test("An ASIN wins over a release group where a file carries both")
    func asinWins() {
        let tags = [("MUSICBRAINZ_RELEASEGROUPID", releaseGroup), ("audible_asin", asin)]

        #expect(AudioTagIdentifiers.identifier(fromTags: tags) == .audibleASIN(asin))
    }

    @Test("A value that is not an identifier is refused before it can reach a request")
    func refusesBadValues() {
        let tags = [("ASIN", "../../etc/passwd"), ("MusicBrainz Release Group Id", "nope")]

        #expect(AudioTagIdentifiers.identifier(fromTags: tags) == nil)
    }

    @Test("Bytes that are no audio container read none rather than throw")
    func refusesNonsense() async {
        #expect(await read((0..<64).map { UInt8($0) }) == nil)
        #expect(await read([]) == nil)
        #expect(await read(Array("ID3".utf8) + [3, 0, 0, 0x7f, 0x7f, 0x7f, 0x7f]) == nil)
    }

    // MARK: Builders

    private func be(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    private func le(_ value: Int) -> [UInt8] {
        be(value).reversed()
    }

    private func syncsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7f), UInt8((value >> 14) & 0x7f), UInt8((value >> 7) & 0x7f), UInt8(value & 0x7f)]
    }

    private func txxx(_ encoding: UInt8, _ description: String, _ value: String) -> [UInt8] {
        if encoding == 1 {
            let bom: [UInt8] = [0xff, 0xfe]
            return [1] + bom + Array(description.utf16).flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
                + [0, 0] + bom + Array(value.utf16).flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
        }
        return [encoding] + Array(description.utf8) + [0] + Array(value.utf8)
    }

    private func frame(_ id: String, _ version: Int, _ body: [UInt8]) -> [UInt8] {
        Array(id.utf8) + (version == 4 ? syncsafe(body.count) : be(body.count)) + [0, 0] + body
    }

    private func id3(_ version: UInt8, _ frames: [UInt8]...) -> [UInt8] {
        let body = frames.flatMap { $0 }
        return Array("ID3".utf8) + [version, 0, 0] + syncsafe(body.count) + body
    }

    private func box(_ type: String, _ parts: [UInt8]...) -> [UInt8] {
        let payload = parts.flatMap { $0 }
        return be(8 + payload.count) + Array(type.utf8) + payload
    }

    private func data(_ value: String) -> [UInt8] {
        box("data", be(1), be(0), Array(value.utf8))
    }

    private func freeform(_ mean: String, _ name: String, _ value: String) -> [UInt8] {
        box("----", box("mean", be(0), Array(mean.utf8)), box("name", be(0), Array(name.utf8)), data(value))
    }

    private func mp4(_ item: [UInt8], mdatBytes: Int = 16) -> [UInt8] {
        let meta = box("meta", be(0), box("hdlr", [UInt8](repeating: 0, count: 24)), box("ilst", item))
        return box("ftyp", Array("M4B ".utf8), be(0)) + box("mdat", [UInt8](repeating: 0, count: mdatBytes))
            + box("moov", box("mvhd", [UInt8](repeating: 0, count: 100)), box("udta", meta))
    }

    private func mp4Keys(_ names: [String], _ values: [Int: String]) -> [UInt8] {
        let keys = box("keys", be(0), be(names.count), box("mdta", Array(names[0].utf8)),
                       box("mdta", Array(names[1].utf8)))
        let ilst = values.flatMap { index, value in be(8 + data(value).count) + be(index) + data(value) }
        let meta = box("meta", be(0), box("hdlr", [UInt8](repeating: 0, count: 24)), keys, box("ilst", ilst))
        return box("ftyp", Array("M4B ".utf8), be(0)) + box("moov", box("udta", meta))
    }

    private func vorbis(_ entries: String...) -> [UInt8] {
        let vendor = Array("test".utf8)
        return le(vendor.count) + vendor + le(entries.count)
            + entries.flatMap { le($0.utf8.count) + Array($0.utf8) }
    }

    private func block(_ type: UInt8, _ body: [UInt8], last: Bool) -> [UInt8] {
        [type | (last ? 0x80 : 0), UInt8((body.count >> 16) & 0xff), UInt8((body.count >> 8) & 0xff),
         UInt8(body.count & 0xff)] + body
    }
}
