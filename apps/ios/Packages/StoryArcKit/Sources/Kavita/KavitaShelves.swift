public import Foundation

/// A collection the server holds.
///
/// Kavita calls this a tag. It groups series and has no order, which is what separates it
/// from a reading list — a distinction worth keeping, because a client that treats them
/// alike is a client that will lose someone's order.
public struct KavitaCollection: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let title: String
    public let summary: String?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary
    }
}

/// A reading list the server holds: an ordered run of chapters.
public struct KavitaReadingList: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let title: String
    public let summary: String?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary
    }
}

/// One entry in a server reading list, in the order the server keeps.
public struct KavitaReadingListItem: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let order: Int
    public let seriesId: Int
    public let chapterId: Int
    public let title: String?
    public let seriesName: String?

    /// What to call it in a list. The chapter's own title, or the series it belongs to.
    public var displayName: String {
        if let title, !title.isEmpty { return title }
        return seriesName ?? ""
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        seriesId = try container.decodeIfPresent(Int.self, forKey: .seriesId) ?? 0
        chapterId = try container.decodeIfPresent(Int.self, forKey: .chapterId) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        seriesName = try container.decodeIfPresent(String.self, forKey: .seriesName)
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, seriesId, chapterId, title, seriesName
    }
}

/// What `update-by-multiple` wants: a list, a series, and the chapters to append.
struct KavitaListAppend: Encodable {
    let readingListId: Int
    let seriesId: Int
    let chapterIds: [Int]
}

extension KavitaClient {
    /// The collections this server holds.
    public func collections() async throws -> [KavitaCollection] {
        try decode([KavitaCollection].self, from: try await get("Collection"))
    }

    /// The series in one collection.
    public func collected(_ id: Int) async throws -> [KavitaSeries] {
        try decode(
            [KavitaSeries].self,
            from: try await get(
                "Collection/series",
                query: [URLQueryItem(name: "collectionId", value: String(id))]
            )
        )
    }

    /// The reading lists this server holds.
    public func readingLists() async throws -> [KavitaReadingList] {
        try decode([KavitaReadingList].self, from: try await get("ReadingList/lists"))
    }

    /// One reading list's entries, in the order the server keeps.
    public func readingListItems(_ id: Int) async throws -> [KavitaReadingListItem] {
        try decode(
            [KavitaReadingListItem].self,
            from: try await get(
                "ReadingList/items",
                query: [URLQueryItem(name: "readingListId", value: String(id))]
            )
        )
    }

    /// Appends chapters to a server reading list.
    ///
    /// `kavita-server` requires the change to be "reflected for other Kavita clients", which
    /// is what sending it rather than keeping it locally buys.
    public func append(toList listId: Int, seriesId: Int, chapterIds: [Int]) async throws {
        guard let url = address.endpoint("ReadingList/update-by-multiple") else {
            throw KavitaError.badAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KavitaListAppend(readingListId: listId, seriesId: seriesId, chapterIds: chapterIds)
        )
        _ = try await send(request)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        return value
    }
}
