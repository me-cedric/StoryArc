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

/// What `create` wants: a name, and nothing else. Kavita fills in the rest.
struct KavitaListDraft: Encodable {
    let title: String
}

/// What `update-for-series` wants: a collection, a name for it, and the series to put in it.
///
/// Zero for the id is Kavita's own way of saying "make one": its bulk-add creates the
/// collection when the id names none. There is no separate create route for a collection the
/// way there is for a reading list.
struct KavitaCollectionDraft: Encodable {
    let collectionTagId: Int
    let collectionTagTitle: String
    let seriesIds: [Int]
}

/// What `update-position` wants: one entry, where it is, and where it goes.
struct KavitaListPosition: Encodable {
    let readingListId: Int
    let readingListItemId: Int
    let fromPosition: Int
    let toPosition: Int
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
    ///
    /// A POST carrying a filter, for the reason ``series(inLibrary:)`` gives: measured
    /// against a live server on 2026-09-06, a GET here is a 404 and this client sent one,
    /// so a reader who added their own Kavita was shown no reading lists at all.
    ///
    /// The other route an older server may not have, so it is asked the way
    /// ``KavitaClient/sendVersioned(_:path:)`` asks: a 404 here is remembered once and
    /// answered with a sentence, and nothing else is read as an old server.
    public func readingLists() async throws -> [KavitaReadingList] {
        guard let url = address.endpoint("ReadingList/lists") else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try decode(
            [KavitaReadingList].self,
            from: try await sendVersioned(request, path: "ReadingList/lists")
        )
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

    /// Makes a collection on the server and answers with what it became.
    ///
    /// `collections-and-reading-lists` lets a reader keep a new collection "on a server if the
    /// user chooses one that supports collections". Kavita has no create route for a
    /// collection: it brings one into being by tagging series, with a zero id meaning "make
    /// it". So the create is a bulk-add, and the id has to be read back afterwards — the
    /// bulk-add answers with nothing, and everything a caller does next is addressed by the
    /// id the server minted. The listing is read on both sides of the create so the new id
    /// can be told from one the server already held under the same name.
    ///
    /// **A collection holding no series has never been made against a live Kavita.** The mock
    /// takes one; a real server may not, because a collection with nothing in it is not a
    /// thing Kavita's own interface can make. That is a live-server question, and
    /// `docs/openspec/STATUS.md` scores it as one.
    public func createCollection(
        named title: String,
        seriesIds: [Int] = []
    ) async throws -> KavitaCollection {
        guard let url = address.endpoint("Collection/update-for-series") else {
            throw KavitaError.badAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KavitaCollectionDraft(
                collectionTagId: 0,
                collectionTagTitle: title,
                seriesIds: seriesIds
            )
        )
        let before = Set(try await collections().map(\.id))
        _ = try await send(request)
        // By id rather than by name. Kavita lists collections by title, so a server that
        // already held one of this name lists two in no reliable order, and the last of them
        // can be the one somebody else made. One of that name is unambiguous either way.
        let named = try await collections().filter { $0.title == title }
        let minted = named.first { !before.contains($0.id) }
        guard let made = minted ?? (named.count == 1 ? named.first : nil) else {
            throw KavitaError.unexpectedResponse
        }
        return made
    }

    /// Moves one entry of a server reading list to a new place in it.
    ///
    /// `collections-and-reading-lists` makes a reading list's order its meaning, and asks
    /// for a new order to be "sent to the server" for a server-backed list. Kavita moves one
    /// entry at a time, by position rather than by identity, so a caller that wants a whole
    /// order sends a run of these — see ``ShelfSync``, which plans that run.
    public func moveInList(_ listId: Int, item: Int, from: Int, to: Int) async throws {
        guard let url = address.endpoint("ReadingList/update-position") else {
            throw KavitaError.badAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KavitaListPosition(
                readingListId: listId,
                readingListItemId: item,
                fromPosition: from,
                toPosition: to
            )
        )
        _ = try await send(request)
    }

    /// Makes a new, empty reading list on the server and answers with what it became.
    ///
    /// `collections-and-reading-lists` lets a reader put a local list "on a server" so it
    /// syncs and is visible elsewhere. The server mints the id, which is why this answers
    /// with the list rather than with nothing: everything that follows — the entries, and
    /// the undo — is addressed by it.
    public func createList(named title: String) async throws -> KavitaReadingList {
        guard let url = address.endpoint("ReadingList/create") else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(KavitaListDraft(title: title))
        return try decode(KavitaReadingList.self, from: try await send(request))
    }

    /// Removes a reading list from the server.
    ///
    /// Here so the copy is reversible: `collections-and-reading-lists` makes every action of
    /// this shape "undoable for 10 seconds", and the only way to take back a list the server
    /// now holds is to ask the server to drop it again.
    public func deleteList(_ id: Int) async throws {
        guard let url = address.endpoint(
            "ReadingList",
            query: [URLQueryItem(name: "readingListId", value: String(id))]
        ) else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await send(request)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        return value
    }
}
