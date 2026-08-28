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
    }

    private enum CodingKeys: String, CodingKey {
        case seriesId, summary, genres, tags, writers, publishers, releaseYear
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
