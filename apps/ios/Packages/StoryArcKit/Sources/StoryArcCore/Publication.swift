public import Foundation

/// Whether a publication can be read without transferring all of it.
///
/// Three states, not two. `publication-formats` needs to distinguish a format
/// that streams from one that must be downloaded first *and* from one that cannot
/// be read at all — collapsing the last two would either promise a download that
/// changes nothing, or refuse a book that would open fine once local.
public enum StreamingCapability: String, Sendable, Codable, CaseIterable {
    /// Pages can be fetched individually from a remote source.
    case streams
    /// Readable, but only once the whole file is local. A solid RAR5, say: every
    /// entry before the target has to be decompressed.
    case downloadOnly
    /// Cannot be read at all, local or remote. A solid RAR4: no decoder with an
    /// OSI-approved licence implements one, so downloading changes nothing.
    case refused
}

/// Where a value came from, which decides whether it may be silently replaced.
///
/// `publication-formats` requires values parsed from a filename to be marked
/// inferred, so a later authoritative source can overwrite them without asking
/// the user to resolve a conflict the app invented. The distinction only matters
/// at the moment of replacement, which is exactly when it is too late to
/// reconstruct.
public enum MetadataOrigin: String, Sendable, Codable, CaseIterable {
    /// Read from the publication: `ComicInfo.xml`, an EPUB package document.
    case embedded
    /// Guessed from the filename.
    case inferred
    /// Supplied by a server or catalogue that owns the answer.
    case authoritative

    /// Whether a value from `other` may replace one from `self` without asking.
    ///
    /// Ordered by how much the source knows: an inferred value yields to anything,
    /// embedded metadata yields only to an authoritative source, and an
    /// authoritative value is never silently overwritten.
    public func yields(to other: MetadataOrigin) -> Bool {
        rank < other.rank
    }

    private var rank: Int {
        switch self {
        case .inferred: 0
        case .embedded: 1
        case .authoritative: 2
        }
    }
}

/// One thing a person can read.
///
/// The library's unit. Assembled by indexing a file — the format layer reads the
/// container and its metadata, and this is what comes out the other side, with no
/// reference to how it was obtained.
public struct Publication: Sendable, Equatable, Identifiable {
    /// Stable across sources, so the same book from a folder and from a server is
    /// one book with one reading position (ADR-0006).
    public let identity: PublicationIdentity

    /// A stable key for lists and diffing.
    ///
    /// Built from whichever identity components exist, in the priority ADR-0006
    /// gives them, so a publication that later gains a server id keeps a usable
    /// key throughout rather than changing identity mid-session.
    public var id: String { identity.stableID }

    public let format: PublicationFormat
    /// How the publication is presented: the title if it has one, else the series
    /// and number, else the filename.
    public let displayTitle: String
    public let series: String?
    /// Issue or chapter. A string: "3.5" and "Annual 1" are both real.
    public let number: String?
    public let volume: Int?
    public let authors: [String]
    public let publisher: String?
    public let year: Int?
    public let language: String?
    public let summary: String?

    /// Where the metadata above came from, and therefore what may replace it.
    public let origin: MetadataOrigin

    /// Pages for a comic, spine items for an EPUB. `nil` when the publication
    /// could not be indexed deeply enough to know.
    public let pageCount: Int?
    /// Entries that looked like pages and could not be read.
    public let skippedPageCount: Int
    /// The path of the cover *inside* the publication, when it has one.
    public let coverPath: String?
    public let readingDirection: ReadingDirection
    public let isFixedLayout: Bool
    public let streaming: StreamingCapability

    /// Which source this came from, when the app knows.
    ///
    /// `library-browsing` asks the library to combine sources and to list "titles from
    /// higher sources first when two sources hold the same publication", and `sources`
    /// asks a source's detail screen for its item count. Neither is answerable without
    /// this, which is why a flat list of files was as far as the library could go.
    ///
    /// Optional, because a publication can arrive without one: a file the system hands
    /// over belongs to no source the reader configured. `nil` means unattributed rather
    /// than unknown-and-probably-local.
    ///
    /// `var` where every other field is `let`, and deliberately: indexing decides what a
    /// publication *is*, and the library decides which source it came from. The indexer
    /// reads bytes and has no idea a registry exists.
    public var sourceID: UUID?

    public init(
        identity: PublicationIdentity,
        format: PublicationFormat,
        displayTitle: String,
        series: String? = nil,
        number: String? = nil,
        volume: Int? = nil,
        authors: [String] = [],
        publisher: String? = nil,
        year: Int? = nil,
        language: String? = nil,
        summary: String? = nil,
        origin: MetadataOrigin,
        pageCount: Int? = nil,
        skippedPageCount: Int = 0,
        coverPath: String? = nil,
        readingDirection: ReadingDirection = .leftToRight,
        isFixedLayout: Bool = false,
        streaming: StreamingCapability = .streams,
        sourceID: UUID? = nil
    ) {
        self.sourceID = sourceID
        self.identity = identity
        self.format = format
        self.displayTitle = displayTitle
        self.series = series
        self.number = number
        self.volume = volume
        self.authors = authors
        self.publisher = publisher
        self.year = year
        self.language = language
        self.summary = summary
        self.origin = origin
        self.pageCount = pageCount
        self.skippedPageCount = skippedPageCount
        self.coverPath = coverPath
        self.readingDirection = readingDirection
        self.isFixedLayout = isFixedLayout
        self.streaming = streaming
    }

    /// Whether the reader can open this at all.
    ///
    /// False only for `refused`. A download-only publication is openable — it just
    /// has to arrive first, which is the library's problem and not the reader's.
    public var isOpenable: Bool { streaming != .refused }

    /// Whether some pages are missing from what the reader will show.
    public var isPartial: Bool { skippedPageCount > 0 }
}

/// The container formats a publication can arrive in.
///
/// Lives in the domain rather than the format layer because the library sorts,
/// filters and explains by format, and none of that should require the parser.
public enum PublicationFormat: String, Sendable, Codable, CaseIterable {
    case cbz, cbr, cb7, cbt, epub, pdf, imageFolder

    /// Whether pages are images rather than reflowable text. Drives which reader
    /// opens the publication, and whether a page curl needs a raster.
    public var isPagedImages: Bool {
        switch self {
        case .cbz, .cbr, .cb7, .cbt, .imageFolder: true
        case .epub, .pdf: false
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
        default: return nil
        }
    }

    /// The media type that names this format, for a record that has to be read back.
    ///
    /// The inverse of ``init(mediaType:)``, and it has to stay the inverse: a download
    /// record keeps a media type and the store names the file on disk from it, so a type
    /// that did not round-trip would write `x.cbz` and later go looking for `x.bin`.
    public var mediaType: String {
        switch self {
        case .cbz: "application/vnd.comicbook+zip"
        case .cbr: "application/vnd.comicbook-rar"
        case .cb7: "application/vnd.comicbook+7z"
        case .cbt: "application/vnd.comicbook+tar"
        case .epub: "application/epub+zip"
        case .pdf: "application/pdf"
        // A folder of images is not a type anybody publishes, and it round-trips through
        // nothing. Named rather than defaulted so the switch stays total, and answered
        // honestly so a caller that needs one file can see there is none.
        case .imageFolder: "inode/directory"
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
        }
    }
}
