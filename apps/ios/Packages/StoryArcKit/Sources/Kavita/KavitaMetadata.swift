public import Foundation

/// A name the server holds for a genre, a tag, a person or a publisher.
public struct KavitaNamed: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let title: String?
    public let name: String?

    /// Kavita calls a genre's name `title` and a person's name `name`. Either will do.
    public var label: String {
        if let title, !title.isEmpty { return title }
        return name ?? ""
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, name
    }
}

/// What the server holds about a series.
///
/// `kavita-server` requires this to be preferred over metadata embedded in the file, because
/// the server is the curated source.
public struct KavitaMetadata: Sendable, Equatable, Decodable {
    public let seriesId: Int
    public let summary: String?
    public let genres: [KavitaNamed]
    public let tags: [KavitaNamed]
    public let writers: [KavitaNamed]
    public let publishers: [KavitaNamed]
    public let releaseYear: Int

    /// Kavita's `AgeRating` and `PublicationStatus`, as the bare integers the API sends.
    ///
    /// Kept as numbers on the model and read through ``KavitaAgeRating`` and
    /// ``KavitaPublicationStatus``, which is where the two rules about them live: an
    /// unrecognised number is not a rating, and two of Kavita's own values are not ratings at
    /// all. Decoding straight into an enum would have to decide what an unknown number means
    /// at the point where the only honest answer is "nothing", and a failed decode would cost
    /// the whole series' metadata rather than one line of it.
    public let ageRating: Int
    public let publicationStatus: Int

    /// The people worth naming on a detail screen, in the order a reader looks for them.
    public var people: [String] {
        (writers + publishers).map(\.label).filter { !$0.isEmpty }
    }

    /// Genres and tags read as one list; the distinction is Kavita's, not the reader's.
    public var subjects: [String] {
        (genres + tags).map(\.label).filter { !$0.isEmpty }
    }

    /// Everything a one-line summary row shows, already in order.
    public var facts: [String] {
        (releaseYear > 0 ? [String(releaseYear)] : []) + people + subjects
    }

    /// Absent fields are normal: Kavita omits what a series does not have.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seriesId = try container.decodeIfPresent(Int.self, forKey: .seriesId) ?? 0
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        genres = try container.decodeIfPresent([KavitaNamed].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([KavitaNamed].self, forKey: .tags) ?? []
        writers = try container.decodeIfPresent([KavitaNamed].self, forKey: .writers) ?? []
        publishers = try container.decodeIfPresent([KavitaNamed].self, forKey: .publishers) ?? []
        releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear) ?? 0
        // `0` is Kavita's own default for both — `Unknown` for the rating and `OnGoing` for
        // the status — so an absent field and a server that never set one read alike, which
        // is what they are.
        ageRating = try container.decodeIfPresent(Int.self, forKey: .ageRating) ?? 0
        publicationStatus = try container.decodeIfPresent(Int.self, forKey: .publicationStatus) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case seriesId, summary, genres, tags, writers, publishers, releaseYear
        case ageRating, publicationStatus
    }
}

extension KavitaClient {
    /// A series cover, as image bytes.
    ///
    /// Kavita's image routes take the key in the query rather than a bearer token, but this
    /// goes through the same request path anyway: one place that knows how to reach the
    /// server is easier to keep correct than two.
    public func seriesCover(_ id: Int) async throws -> Data {
        try await get("Image/series-cover", query: [
            URLQueryItem(name: "seriesId", value: String(id)),
            URLQueryItem(name: "apiKey", value: address.apiKey),
        ])
    }

    /// A chapter cover, as image bytes.
    public func chapterCover(_ id: Int) async throws -> Data {
        try await get("Image/chapter-cover", query: [
            URLQueryItem(name: "chapterId", value: String(id)),
            URLQueryItem(name: "apiKey", value: address.apiKey),
        ])
    }

    /// What the server holds about a series, which the spec prefers over the file's own.
    public func metadata(ofSeries id: Int) async throws -> KavitaMetadata {
        let data = try await get(
            "Series/metadata",
            query: [URLQueryItem(name: "seriesId", value: String(id))]
        )
        guard let value = try? JSONDecoder().decode(KavitaMetadata.self, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        return value
    }

    /// The chapter the reader should open next in a series.
    ///
    /// Asked of the server rather than worked out from the chapter list: Kavita knows what
    /// other devices have read, and this app may not have pulled that yet.
    public func continuePoint(ofSeries id: Int) async throws -> KavitaChapter {
        let data = try await get(
            "Reader/continue-point",
            query: [URLQueryItem(name: "seriesId", value: String(id))]
        )
        guard let value = try? JSONDecoder().decode(KavitaChapter.self, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        return value
    }
}

/// Where a reader got to in one chapter, in the shape Kavita's own progress endpoint wants.
///
/// The whole chain, not the chapter alone: Kavita keys its progress rows by library, series,
/// volume and chapter together, and a post missing one of them is refused.
public struct KavitaPosition: Sendable, Equatable, Codable {
    public let libraryId: Int
    public let seriesId: Int
    public let volumeId: Int
    public let chapterId: Int
    public let pageNum: Int

    public init(libraryId: Int, seriesId: Int, volumeId: Int, chapterId: Int, pageNum: Int) {
        self.libraryId = libraryId
        self.seriesId = seriesId
        self.volumeId = volumeId
        self.chapterId = chapterId
        self.pageNum = pageNum
    }
}

extension KavitaClient {
    /// Tells the server where the reader got to.
    ///
    /// `kavita-server`: the page position is sent "when a user reads a Kavita publication and
    /// leaves the reader".
    public func report(_ position: KavitaPosition) async throws {
        guard let url = address.endpoint("Reader/progress") else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(position)
        _ = try await send(request)
    }
}

/// Which chapter to mark, in the shape Kavita's mark endpoints want.
struct KavitaMark: Encodable {
    let seriesId: Int
    let chapterId: Int
}

extension KavitaClient {
    /// Marks one chapter read or unread on the server.
    ///
    /// `kavita-server` asks for the state to be "reflected in that server's own UI", which a
    /// position cannot do on its own: page zero of an unread chapter and page zero of a
    /// chapter the reader deliberately unmarked are the same number.
    public func mark(seriesId: Int, chapterId: Int, isRead: Bool) async throws {
        let path = isRead ? "Reader/mark-chapter-read" : "Reader/mark-chapter-unread"
        guard let url = address.endpoint(path) else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KavitaMark(seriesId: seriesId, chapterId: chapterId)
        )
        _ = try await send(request)
    }
}
