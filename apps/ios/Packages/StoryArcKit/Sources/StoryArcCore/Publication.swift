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
/// `Codable` because every field of it is durable, which is not true of every domain type
/// here — `Source` deliberately has no conformance, because its connection state describes
/// a network and a state read back from disk is a claim about the past. A publication has
/// no such field: title, series, format and page count are as true tomorrow as today, so
/// caching the whole of it is honest rather than convenient. `sources` asks for the
/// catalogue to be cached so the library "opens instantly and stays browsable while
/// offline", and this is what makes that a write rather than a translation layer.
public struct Publication: Sendable, Equatable, Identifiable, Codable {
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

    /// What kind of thing this is: "Superhero", "Manga", "Science Fiction".
    ///
    /// `library-browsing` filters by genre and by tag, and keeps them apart because
    /// the files do: `ComicInfo.xml` writes `<Genre>` for the shelf a publication
    /// belongs on and `<Tags>` for whatever else the cataloguer wanted to record.
    /// Merging them would make one filter out of two the reader can tell apart.
    ///
    /// Empty rather than `nil`: a publication with no genre and a publication whose
    /// genre list is empty are the same thing, and an optional array would offer a
    /// distinction nothing can act on.
    public let genres: [String]
    /// Free-form labels the cataloguer added. See ``genres``.
    public let tags: [String]

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

    /// How much disk the publication occupies, when the app has been told.
    ///
    /// `library-browsing` sorts by file size, and no container reports its own
    /// length from the inside — the walk that found the file is what knows it, the
    /// same way it knows when the file arrived. `nil` for a publication reached
    /// somewhere the size was never asked for, which sorts as unknown rather than
    /// as zero bytes.
    public var fileSize: Int64?

    /// When the file was last written, as the filesystem reports it.
    ///
    /// `local-library` asks a returning app to reconcile "by comparing file modification
    /// times and sizes rather than re-reading every archive". This is the other half of
    /// that comparison — cheap to read from a directory entry, and enough, with the size,
    /// to say that a container has not changed since it was last indexed.
    public var modifiedAt: Date?

    /// When the file arrived where the app found it.
    ///
    /// `library-browsing` sorts by date added, and there is nowhere else for the
    /// date to come from: StoryArc keeps no record of publications between
    /// launches, so the only thing that remembers when a comic turned up is the
    /// filesystem it turned up in.
    ///
    /// `var`, like `sourceID` and for the same reason: the container decides what a
    /// publication *is*, and the two facts above are about the file rather than the
    /// book. Threading them through every constructor would say they were the same
    /// kind of answer.
    public var addedAt: Date?

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
        genres: [String] = [],
        tags: [String] = [],
        origin: MetadataOrigin,
        pageCount: Int? = nil,
        skippedPageCount: Int = 0,
        coverPath: String? = nil,
        readingDirection: ReadingDirection = .leftToRight,
        isFixedLayout: Bool = false,
        streaming: StreamingCapability = .streams,
        sourceID: UUID? = nil,
        fileSize: Int64? = nil,
        modifiedAt: Date? = nil,
        addedAt: Date? = nil
    ) {
        self.sourceID = sourceID
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.addedAt = addedAt
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
        self.genres = genres
        self.tags = tags
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

    /// Whether this publication still describes the file on disk.
    ///
    /// `local-library`: a returning app reconciles "by comparing file modification times
    /// and sizes rather than re-reading every archive". This is that comparison, and the
    /// reason it is worth having is what it avoids — opening a container, reading its
    /// central directory and its metadata, per publication, to learn nothing.
    ///
    /// Unknown facts mean *not* unchanged. A publication indexed before these were
    /// recorded, or a file the walk could not stat, is re-read rather than trusted: the
    /// cost of a needless re-index is a slow scan, and the cost of a wrong reuse is a
    /// library that disagrees with the disk and never notices.
    public func matchesFile(size: Int64?, modifiedAt moment: Date?) -> Bool {
        guard let fileSize, let modifiedAt, let size, let moment else { return false }
        return fileSize == size && modifiedAt == moment
    }

    /// Whether some pages are missing from what the reader will show.
    public var isPartial: Bool { skippedPageCount > 0 }

    /// Whether the text in this publication reflows.
    ///
    /// The same question `TransitionChoices` asks under the same name — there it is a
    /// parameter, because the axis a publication implies depends on it. Here it is the
    /// publication's own answer, written down in the domain because the format alone does
    /// not give it and everyone assumes it does: a **fixed-layout** EPUB is an EPUB by
    /// format and a stack of pictures in fact.
    ///
    /// `StoryArcApp` routes on this, and that is a consequence rather than the definition.
    /// `ebook-reader` gives a fixed-layout EPUB the pagination, zoom and spread behaviour of
    /// `comic-reader` and hides the typography controls rather than showing them disabled,
    /// and this app implements that by opening the comic reader — which has no typography
    /// controls to hide. The same scenario also asks that background colour, brightness and
    /// page transition stay available there; brightness and the page transition are, in
    /// `AdjustmentsSheet` and in `ReaderChrome`'s transition picker, and there is no
    /// background-colour control in that reader. So this routing satisfies the first half of
    /// that scenario and leaves the second half open.
    ///
    /// **Android has the rule and not the name.** `AppShell.kt` still writes
    /// `publication.format == PublicationFormat.EPUB && !publication.isFixedLayout` inline in
    /// the branch that starts the activity, and `grep -rn isReflowable apps/android` finds
    /// only `TransitionChoices`. One rule, one protection: the Kotlin side has neither the
    /// property nor a guard, and this note is here so the next hand to touch either does not
    /// have to notice on its own.
    ///
    /// It has a name and a test because the unnamed version was a clause in a view body that
    /// two UI audits walked past. Both asked the shelf for "an EPUB" — a cover's spoken label
    /// carries the format and says nothing about the layout — so neither run recorded which
    /// of the two readers it reached. ``ReaderRoutingWiringTests`` guards the routing itself;
    /// this property's own suite is `IsReflowableTests`.
    public var isReflowable: Bool { format == .epub && !isFixedLayout }
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
        case .imageFolder: nil
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
