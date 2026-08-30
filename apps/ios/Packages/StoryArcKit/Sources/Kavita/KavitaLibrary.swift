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

    public init(id: Int, name: String, libraryId: Int, pages: Int = 0, pagesRead: Int = 0) {
        self.id = id
        self.name = name
        self.libraryId = libraryId
        self.pages = pages
        self.pagesRead = pagesRead
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, libraryId, pages, pagesRead

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

    /// What to call it in a list.
    ///
    /// The title when the server has one, the number when it does not. Kavita leaves the
    /// title empty for a plain numbered issue, and "Chapter 3" beats an empty row.
    public var displayName: String {
        if let title, !title.isEmpty { return title }
        return number
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
    /// Kavita models loose chapters as a volume numbered zero. `kavita-server` requires the
    /// detail screen to list "volumes and loose chapters in Kavita's own order, clearly
    /// distinguishing the two", and this is the distinction — without it, every series with
    /// loose chapters shows a phantom "Volume 0".
    public var isLooseChapters: Bool { number == 0 }
}

extension KavitaClient {
    /// The server's libraries.
    public func libraries() async throws -> [KavitaLibraryFolder] {
        try decode([KavitaLibraryFolder].self, from: try await get("Library/libraries"))
    }

    /// The series in one library, or in all of them.
    public func series(inLibrary id: Int? = nil) async throws -> [KavitaSeries] {
        let query = id.map { [URLQueryItem(name: "libraryId", value: String($0))] } ?? []
        return try decode([KavitaSeries].self, from: try await get("Series/all-v2", query: query))
    }

    /// One series, asked for by identity.
    ///
    /// A search result names a series and the library it belongs to is not always in the
    /// answer — and Kavita keys progress by library *and* series, so opening a found series
    /// without asking would report reading against library zero, which the server refuses.
    /// One request on a tap, rather than a wrong write on every page turn afterwards.
    public func seriesDetail(_ id: Int) async throws -> KavitaSeries {
        try decode(KavitaSeries.self, from: try await get("Series/\(id)"))
    }

    /// The volumes of one series, each with its chapters.
    public func volumes(ofSeries id: Int) async throws -> [KavitaVolume] {
        try decode(
            [KavitaVolume].self,
            from: try await get(
                "Series/volumes",
                query: [URLQueryItem(name: "seriesId", value: String(id))]
            )
        )
    }

    /// One chapter's bytes.
    ///
    /// The media type comes back with the bytes because a Kavita library holds comics and
    /// books alike: writing every chapter to disk as `.cbz` sent an EPUB to the comic
    /// reader, which spun for ever on a file it could not page.
    public func chapter(_ id: Int) async throws -> KavitaFile {
        guard let url = address.endpoint(
            "Download/chapter",
            query: [URLQueryItem(name: "chapterId", value: String(id))]
        ) else { throw KavitaError.badAddress }
        var type: String?
        let bytes = try await send(URLRequest(url: url)) { type = $0 }
        return KavitaFile(bytes: bytes, mediaType: type)
    }

    /// Series matching a query, answered by the server.
    ///
    /// The narrow half of ``find(_:)``, kept because the series is the only thing a caller
    /// that already knows which library it is in needs.
    public func search(_ query: String) async throws -> [KavitaSeries] {
        try await results(for: query).series
    }

    /// Everything the server matched, in the five kinds the spec names.
    ///
    /// `kavita-server`: searching within a Kavita source sends the query to the server,
    /// "returning matches across series, chapters, people, genres, and tags — not only
    /// titles cached locally". The doc comment this replaced said only the series half was
    /// read because "the rest needs screens that do not exist yet" — the screen exists now,
    /// so the rest is read.
    ///
    /// Genres and tags arrive as one kind, for the reason ``KavitaHit/Kind/subject`` gives.
    /// A person and a subject carry no series, because Kavita answers them with a name
    /// alone.
    public func find(_ query: String) async throws -> [KavitaHit] {
        let found = try await results(for: query)
        return found.series.map { KavitaHit(kind: .series, title: $0.name, seriesId: $0.id) }
            + found.chapters.map {
                KavitaHit(kind: .chapter, title: $0.displayName, seriesId: $0.seriesId)
            }
            + found.persons.map { KavitaHit(kind: .person, title: $0.label) }
            + (found.genres + found.tags).map { KavitaHit(kind: .subject, title: $0.label) }
    }

    private func results(for query: String) async throws -> KavitaSearchResults {
        let data = try await get(
            "Search/search",
            query: [URLQueryItem(name: "queryString", value: query)]
        )
        return try decode(KavitaSearchResults.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        return value
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
