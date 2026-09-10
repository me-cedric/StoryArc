public import Foundation

public import StoryArcCore

/// One of a Kavita server's libraries.
///
/// `kavita-server` requires the app to "mirror Kavita's own structure — libraries, series,
/// volumes, and chapters — rather than flattening it". A reader who arranged their server
/// into Comics and Books arranged it for a reason.
public struct KavitaLibraryFolder: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// A series, as the library list shows it.
public struct KavitaSeries: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let libraryId: Int

    /// Pages in the whole series, and how many of them the server says are read.
    public let pages: Int
    public let pagesRead: Int
    /// Kavita's `MangaFormat`: 0 image, 1 archive, 2 unknown, 3 epub, 4 pdf.
    ///
    /// Defaulted, because a search result does not carry it. Read by the library, which has
    /// to file a server's publication under a format before anything is downloaded.
    public let format: Int

    public init(
        id: Int,
        name: String,
        libraryId: Int,
        pages: Int = 0,
        pagesRead: Int = 0,
        format: Int = 0
    ) {
        self.id = id
        self.name = name
        self.libraryId = libraryId
        self.pages = pages
        self.pagesRead = pagesRead
        self.format = format
    }

    /// Page counts default to nothing rather than being required.
    ///
    /// Kavita's search results carry a series' identity and not its progress, and a decoder
    /// that insisted would turn every search into "unexpected response". Identity is still
    /// required, because a series without it is not a series — and a search result spells it
    /// `seriesId` where a library listing spells it `id`, so both are read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let identity = try container.decodeIfPresent(Int.self, forKey: .id)
            ?? container.decodeIfPresent(Int.self, forKey: .seriesId)
        else { throw KavitaError.unexpectedResponse }
        id = identity
        name = try container.decode(String.self, forKey: .name)
        libraryId = try container.decodeIfPresent(Int.self, forKey: .libraryId) ?? 0
        pages = try container.decodeIfPresent(Int.self, forKey: .pages) ?? 0
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
        format = try container.decodeIfPresent(Int.self, forKey: .format) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, libraryId, pages, pagesRead, format

        /// What a search result calls a series' identity.
        case seriesId
    }

    /// How far through, for the progress a series row shows.
    ///
    /// `nil` for a series with no pages, rather than zero: a server still scanning reports
    /// nothing, and a bar at zero would say "unread" about something it does not yet know.
    public var fraction: Double? {
        guard pages > 0 else { return nil }
        return min(1, Double(pagesRead) / Double(pages))
    }
}

/// A chapter — the thing a reader actually opens.
public struct KavitaChapter: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int

    /// Kavita's own chapter number, as a string because it can be `1`, `1.5` or `Special`.
    public let number: String

    public let title: String?
    public let pages: Int
    public let pagesRead: Int

    /// Which series it belongs to, when the answer said.
    ///
    /// Zero inside a volume, where the series is the screen the reader is already on. A
    /// search result is the case that needs it: a chapter found by name is the only kind of
    /// row that arrives with no series around it, and without this it could be listed and
    /// not opened.
    public let seriesId: Int

    public init(
        id: Int,
        number: String,
        title: String? = nil,
        pages: Int = 0,
        pagesRead: Int = 0,
        seriesId: Int = 0
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.pages = pages
        self.pagesRead = pagesRead
        self.seriesId = seriesId
    }

    /// Counts default to nothing, for the reason ``KavitaSeries`` gives.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .titleName)
        pages = try container.decodeIfPresent(Int.self, forKey: .pages) ?? 0
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
        seriesId = try container.decodeIfPresent(Int.self, forKey: .seriesId) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, title, pages, pagesRead, seriesId

        /// What a search result calls a chapter's title. Kavita's own search DTO differs
        /// from its volume DTO here, and a chapter found by name would otherwise be listed
        /// as a bare number.
        case titleName
    }

    /// The chapter's issue number, or `nil` where Kavita is saying it has none.
    ///
    /// **`-100000` is a sentinel, not a number.** Kavita writes it for a chapter with no
    /// number at all — a collected edition, a volume with one part — and any negative is
    /// treated the same way, because none of them is an issue number. One place, here,
    /// because every screen that draws a chapter needs the same answer and the ones that
    /// asked separately disagreed: a reader met "-100000" as a row in a chapter list, as
    /// "Continue -100000", and as the name of a downloaded file. Android's
    /// `KavitaChapter.issueNumber` is the twin.
    public var issueNumber: String? {
        guard !number.isEmpty, !number.hasPrefix("-") else { return nil }
        return number
    }

    /// What to call it in a list, or empty when the server gave nothing to call it.
    ///
    /// The title when the server has one, the number when it does not, and *nothing* when
    /// the number is the sentinel — an empty string rather than a made-up label, because
    /// what to say instead is the screen's decision and a screen has its own words for it.
    /// Kavita leaves the title empty for a plain numbered issue, and "3" beats an empty row.
    public var displayName: String {
        if let title, !title.isEmpty { return title }
        return issueNumber ?? ""
    }

    public var isFinished: Bool { pages > 0 && pagesRead >= pages }
}

/// A volume, which is a named group of chapters.
public struct KavitaVolume: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let number: Int
    public let name: String?
    public let chapters: [KavitaChapter]

    public init(id: Int, number: Int, name: String? = nil, chapters: [KavitaChapter] = []) {
        self.id = id
        self.number = number
        self.name = name
        self.chapters = chapters
    }

    /// A volume with no chapters listed is a volume with no chapters, not a failure.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        number = try container.decodeIfPresent(Int.self, forKey: .number) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        chapters = try container.decodeIfPresent([KavitaChapter].self, forKey: .chapters) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, name, chapters
    }

    /// Whether this is Kavita's holder for chapters that belong to no volume.
    ///
    /// `kavita-server` requires the detail screen to list "volumes and loose chapters in
    /// Kavita's own order, clearly distinguishing the two", and this is the distinction —
    /// without it, every series with loose chapters shows a heading the server never meant
    /// as one.
    ///
    /// **Two numbers, because Kavita changed its mind.** Older servers held loose chapters
    /// in a volume numbered zero; current ones use ``looseLeafVolume``. Both are accepted,
    /// so a reader on either server sees the same screen. Android's `isLooseChapters` is
    /// the twin.
    public var isLooseChapters: Bool { number == KavitaVolume.looseLeafVolume || number == 0 }

    /// Whether this is Kavita's holder for specials — annuals, one-shots, anything filed
    /// outside the run.
    ///
    /// A third kind, and the reason the heading needs three cases rather than two: this
    /// volume had no case of its own, so a reader met "100000" as a heading.
    public var isSpecials: Bool { number == KavitaVolume.specialVolume }

    /// Kavita's holder for chapters that belong to no volume.
    ///
    /// Quoted from `Kavita.Models/Constants/ParserConstants.cs`:
    /// `public const int LooseLeafVolumeNumber = -100_000;`
    public static let looseLeafVolume = -100_000

    /// Kavita's holder for specials.
    ///
    /// Quoted from the same file: `public const int SpecialVolumeNumber = 100_000;`.
    /// **It is positive**, so a guard written against negative sentinels does not catch it.
    /// That is how this one was missed while the chapter sentinel beside it was guarded.
    public static let specialVolume = 100_000
}

/// Kavita's `SeriesFilterV2Dto`, of the parts this app sends.
///
/// `Kavita.Models/DTOs/Filtering/v2/Requests/SeriesFilterV2Dto.cs` carries `id`, `name`,
/// `statements`, `combination` and `sortOptions`. This app sends the two it has a use for,
/// because a field nobody measured is a field this client cannot claim a meaning for.
struct KavitaFilter: Encodable {
    /// One clause of the filter.
    ///
    /// `field` 19 is `Libraries` in `SeriesFilterField.cs`, line 29. `comparison` 0 narrowed
    /// a live server on 2026-09-06; the values from 1 to 10 either narrowed the same way or
    /// were ignored, so this app sends the one it measured. `value` is a string on the wire
    /// even when it names a number, which is how Kavita's own client sends it.
    struct Statement: Encodable {
        let comparison: Int
        let field: Int
        let value: String
    }

    let statements: [Statement]

    /// `FilterCombination.And`, which is what one statement needs and what more would want.
    let combination: Int

    /// The filter for one library.
    init(library: Int) {
        statements = [Statement(comparison: 0, field: 19, value: String(library))]
        combination = 0
    }
}

/// A file the server sent, with the type it declared.
///
/// The type is not decoration: a Kavita library holds comics and books alike, and the
/// reader the app opens is chosen by what the file is.
public struct KavitaFile: Sendable, Equatable {
    public let bytes: Data
    public let mediaType: String?

    public init(bytes: Data, mediaType: String?) {
        self.bytes = bytes
        self.mediaType = mediaType
    }
}

/// What `Search/search` returns, of what this app reads.
///
/// Every list defaults to empty. Kavita omits the kinds a query matched nothing in, and a
/// decoder that insisted on all five would turn every narrow search into "unexpected
/// response".
struct KavitaSearchResults: Decodable {
    let series: [KavitaSeries]
    let chapters: [KavitaChapter]

    /// Kavita's own spelling. Renamed on the way out, because `people` is what the rest of
    /// this app calls them.
    let persons: [KavitaNamed]

    let genres: [KavitaNamed]
    let tags: [KavitaNamed]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        series = try container.decodeIfPresent([KavitaSeries].self, forKey: .series) ?? []
        chapters = try container.decodeIfPresent([KavitaChapter].self, forKey: .chapters) ?? []
        persons = try container.decodeIfPresent([KavitaNamed].self, forKey: .persons) ?? []
        genres = try container.decodeIfPresent([KavitaNamed].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([KavitaNamed].self, forKey: .tags) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case series, chapters, persons, genres, tags
    }
}
