import Foundation

/// The container formats a publication can arrive in.
///
/// Lives in the domain rather than the format layer because the library sorts,
/// filters and explains by format, and none of that should require the parser.
public enum PublicationFormat: String, Sendable, Codable, CaseIterable {
    case cbz, cbr, cb7, cbt, epub, pdf, imageFolder
    // The audio containers, and not one flat `audiobook` case. `publication-formats` asks
    // an audiobook to keep "the media type of the container the file actually is, so the
    // file is written back under that container's own extension" — and a flat case has no
    // media type to give, so a copied MP3 was written back as an `.m4b`. An `.m4b` and an
    // `.m4a` are still one case, because both are `audio/mp4` and the contents are the
    // fact. Android's enum made the same call first.
    case m4b, mp3, flac, ogg
    /// A directory of ordered audio files, played as one publication.
    case audioFolder

    /// Whether pages are images rather than reflowable text. Drives which reader
    /// opens the publication, and whether a page curl needs a raster.
    public var isPagedImages: Bool {
        switch self {
        case .cbz, .cbr, .cb7, .cbt, .imageFolder: true
        case .epub, .pdf, .m4b, .mp3, .flac, .ogg, .audioFolder: false
        }
    }

    /// Whether a player rather than a reader opens this.
    ///
    /// The question `FormatSniffer.Container.isAudio` answers about *bytes*, asked here
    /// about a publication that has already been indexed — a screen holds one of these and
    /// never the container it came from. Asked in one place for the same reason: a `switch`
    /// repeated at three call sites is how two of them end up disagreeing.
    public var isAudio: Bool {
        switch self {
        case .m4b, .mp3, .flac, .ogg, .audioFolder: true
        case .cbz, .cbr, .cb7, .cbt, .epub, .pdf, .imageFolder: false
        }
    }

    /// The format a media type names, when it names one this app can read.
    ///
    /// For a catalogue, where the file has not been fetched and its type is all there is.
    /// `opds-catalog` needs this twice: to pick the best acquisition when several are
    /// offered, and to mark an entry unreadable when none of them map.
    ///
    /// Parameters after a semicolon are ignored — several servers append `;charset=utf-8`
    /// to `application/epub+zip`, and an exact-match table would call that unreadable.
    public init?(mediaType: String) {
        let bare = mediaType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""

        switch bare {
        case "application/epub+zip": self = .epub
        case "application/pdf": self = .pdf
        case "application/vnd.comicbook+zip", "application/x-cbz": self = .cbz
        case "application/vnd.comicbook-rar", "application/x-cbr": self = .cbr
        case "application/vnd.comicbook+tar", "application/x-cbt": self = .cbt
        // Listed so a catalogue entry can be *named* as unreadable rather than dropped.
        // `publication-formats` leaves CB7 undecoded, and the refusal has to say which
        // format it refused.
        case "application/vnd.comicbook+7z", "application/x-cb7": self = .cb7
        default:
            guard let audio = Self.audio(bare) else { return nil }
            self = audio
        }
    }

    /// The audio container a media type names.
    ///
    /// A table of its own because the audio spellings outnumber every other format's: a share
    /// sheet and a file provider disagree about the same file, so an `.m4b` arrives as
    /// `audio/x-m4b` from most of them and as `audio/mp4` from the rest. Android's table
    /// carries the same aliases.
    ///
    /// - Parameter bare: a media type with its parameters already stripped and lowercased.
    private static func audio(_ bare: String) -> PublicationFormat? {
        switch bare {
        case "audio/mp4", "audio/m4b", "audio/x-m4b", "audio/m4a", "audio/x-m4a",
             "audio/aac", "audio/aacp": .m4b
        case "audio/mpeg", "audio/mp3", "audio/x-mp3", "audio/mpeg3": .mp3
        case "audio/flac", "audio/x-flac": .flac
        case "audio/ogg", "audio/x-ogg", "audio/opus", "audio/vorbis": .ogg
        default: nil
        }
    }

    /// The media type that names this format — the inverse of ``init(mediaType:)``.
    ///
    /// `nil` for a folder of images, which is not a file and has no type of its own.
    ///
    /// Needed by `local-library`'s imported copies: the record of a copy on the device
    /// stores a media type, and the store works the file's extension back out of it. A
    /// format whose type did not round-trip would be written as `Bone.cbz` and looked for
    /// as `Bone.bin`, which is a copy the app can no longer find.
    public var mediaType: String? {
        switch self {
        case .cbz: "application/vnd.comicbook+zip"
        case .cbr: "application/vnd.comicbook-rar"
        case .cb7: "application/vnd.comicbook+7z"
        case .cbt: "application/vnd.comicbook+tar"
        case .epub: "application/epub+zip"
        case .pdf: "application/pdf"
        // A folder is not a file and has no type of its own, on either platform.
        case .imageFolder, .audioFolder: nil
        case .m4b: "audio/mp4"
        case .mp3: "audio/mpeg"
        case .flac: "audio/flac"
        case .ogg: "audio/ogg"
        }
    }

    /// Whether StoryArc can open a publication in this format today.
    ///
    /// CB7 is the one that parses as a format and does not open: `publication-formats`
    /// records 7-Zip as an open question, and the app names the refusal rather than
    /// pretending the file is not there.
    public var isOpenable: Bool { self != .cb7 }

    /// How the format is named to a person — in a refusal, a filter, a detail row.
    ///
    /// `publication-formats` forbids a generic failure, and a name is what makes
    /// the difference between "7-Zip is not supported" and "could not open file".
    public var displayName: String {
        switch self {
        case .cbz: "CBZ"
        case .cbr: "CBR"
        case .cb7: "CB7"
        case .cbt: "CBT"
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .imageFolder: "Folder"
        case .m4b: "M4B"
        case .mp3: "MP3"
        case .flac: "FLAC"
        case .ogg: "Ogg"
        case .audioFolder: "Audiobook folder"
        }
    }
}
