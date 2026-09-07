import Testing

@testable import StoryArcCore

/// That an audiobook carries the container it actually is, and can be named back from it.
///
/// `publication-formats`: a downloaded or copied audiobook keeps "the media type of the
/// container the file actually is, so the file is written back under that container's own
/// extension", and "an MP3 is not written back as an M4B". One flat `audiobook` case had no
/// media type to give, so every audio download landed as `Title.bin`.
///
/// Mirrors Android's `AudiobookFormatTest`. The media types are asserted as literals rather
/// than only round-tripped, because a round trip stays green while one platform drifts: the
/// two tables are the contract between the platforms, and a record written on one device is
/// read on the other.
@Suite("Audiobook formats")
struct AudiobookFormatTests {

    private let audioFiles: [PublicationFormat] = [.m4b, .mp3, .flac, .ogg]

    private let reading: [PublicationFormat] = [.cbz, .cbr, .cb7, .cbt, .epub, .pdf, .imageFolder]

    @Test("The table is these twelve and nothing else")
    func theWholeTable() {
        #expect(PublicationFormat.allCases.count == audioFiles.count + reading.count + 1)
    }

    @Test("An audio format opens in the player and never pages through images")
    func audioIsAudio() {
        for format in audioFiles + [.audioFolder] {
            #expect(format.isAudio, "\(format) should be audio")
            #expect(!format.isPagedImages, "\(format) should not be paged images")
            #expect(format.isOpenable, "\(format) should open")
            #expect(!format.displayName.isEmpty, "\(format) needs a name to refuse or filter by")
        }
        for format in reading {
            #expect(!format.isAudio, "\(format) should not be audio")
        }
    }

    @Test("Every audio file format round-trips through its media type")
    func roundTrip() throws {
        for format in audioFiles {
            let mediaType = try #require(format.mediaType, "\(format) has no media type")
            #expect(PublicationFormat(mediaType: mediaType) == format)
        }
    }

    /// Android's table, copied. A change on one platform that is not made on the other fails
    /// here rather than at a reader's device, where it looks like a download that will not open.
    @Test("The media types are the ones Android answers")
    func theSameTableAsAndroid() {
        #expect(PublicationFormat.m4b.mediaType == "audio/mp4")
        #expect(PublicationFormat.mp3.mediaType == "audio/mpeg")
        #expect(PublicationFormat.flac.mediaType == "audio/flac")
        #expect(PublicationFormat.ogg.mediaType == "audio/ogg")
    }

    /// The scenario, as a type assertion: "an `.m4b` and an `.m4a` holding the same audio are
    /// treated identically, because the extension is a hint and the contents are the fact".
    @Test("An M4A and an M4B are one format")
    func oneMpegFourCase() {
        #expect(PublicationFormat(mediaType: "audio/mp4") == .m4b)
        #expect(PublicationFormat(mediaType: "audio/x-m4b") == .m4b)
        #expect(PublicationFormat(mediaType: "audio/x-m4a") == .m4b)
    }

    @Test("A media type with parameters still names its format")
    func parametersAreIgnored() {
        #expect(PublicationFormat(mediaType: "audio/mpeg; charset=utf-8") == .mp3)
    }

    /// A folder is not a file. Null on both platforms, and the download path relies on it:
    /// there is no container to write a folder back under.
    @Test("A folder has no media type of its own")
    func aFolderHasNoType() {
        #expect(PublicationFormat.audioFolder.mediaType == nil)
        #expect(PublicationFormat.imageFolder.mediaType == nil)
    }

    /// The protection is refused by name, so it is never a format. A locked file that mapped
    /// to one would be offered for download and would fail on the device.
    @Test("A protected audiobook is no format at all")
    func lockedIsNotAFormat() {
        #expect(PublicationFormat(mediaType: "audio/vnd.audible.aax") == nil)
        #expect(PublicationFormat(mediaType: "audio/vnd.audible.aaxc") == nil)
    }
}
