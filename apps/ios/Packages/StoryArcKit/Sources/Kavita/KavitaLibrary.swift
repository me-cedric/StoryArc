public import Foundation

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
public struct KavitaSeries: Sendable, Equatable, Identifiable, Decodable {
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
    /// required, because a series without it is not a series.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        libraryId = try container.decodeIfPresent(Int.self, forKey: .libraryId) ?? 0
        pages = try container.decodeIfPresent(Int.self, forKey: .pages) ?? 0
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, libraryId, pages, pagesRead
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

    public init(id: Int, number: String, title: String? = nil, pages: Int = 0, pagesRead: Int = 0) {
        self.id = id
        self.number = number
        self.title = title
        self.pages = pages
        self.pagesRead = pagesRead
    }

    /// Counts default to nothing, for the reason ``KavitaSeries`` gives.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        pages = try container.decodeIfPresent(Int.self, forKey: .pages) ?? 0
        pagesRead = try container.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, title, pages, pagesRead
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
    public func chapter(_ id: Int) async throws -> Data {
        try await get(
            "Download/chapter",
            query: [URLQueryItem(name: "chapterId", value: String(id))]
        )
    }

    /// Series matching a query, answered by the server.
    ///
    /// `kavita-server`: searching within a Kavita source sends the query to the server,
    /// "returning matches across series, chapters, people, genres, and tags — not only
    /// titles cached locally". Only the series half is read here; the rest needs screens
    /// that do not exist yet, and decoding fields nothing shows would be pretending.
    public func search(_ query: String) async throws -> [KavitaSeries] {
        let data = try await get(
            "Search/search",
            query: [URLQueryItem(name: "queryString", value: query)]
        )
        return try decode(KavitaSearchResults.self, from: data).series
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        return value
    }
}

/// What `Search/search` returns, of what this app reads.
struct KavitaSearchResults: Decodable {
    let series: [KavitaSeries]
}
