public import Foundation

public import StoryArcCore

/// What the client asks a Kavita server for, and what comes back.
///
/// Split from `KavitaLibrary.swift` when that file passed the 400-line cap this project
/// enforces. The division is the one that was already there: the models a server's answer
/// decodes into stayed, and the requests that fetch them came here.

extension KavitaClient {
    /// The server's libraries.
    public func libraries() async throws -> [KavitaLibraryFolder] {
        try decode([KavitaLibraryFolder].self, from: try await get("Library/libraries"))
    }

    /// The series in one library, or in all of them.
    ///
    /// A POST carrying a filter, because that is what Kavita answers. Measured against a
    /// live server on 2026-09-06: a GET here is a 404, and this client sent one — so a
    /// reader who added their own Kavita was shown no series at all. An empty filter is
    /// the whole list.
    ///
    /// **The library is a statement in the body, not a query parameter.** The same
    /// measurement: `POST /api/Series/all-v2?libraryId=3` answered all 215 series across
    /// four libraries, so the parameter this client used to send did nothing at all, and
    /// the request succeeded — so a reader who picked one library was shown every library
    /// and nothing reported a problem. The statement below answered 91 series from library
    /// 3 alone. See ``KavitaFilter`` for the field and comparison numbers.
    ///
    /// A filter that cannot be encoded throws rather than widening. A listing that quietly
    /// fell back to the whole server is the defect this replaces, not a safe default.
    public func series(inLibrary id: Int? = nil) async throws -> [KavitaSeries] {
        guard let url = address.endpoint("Series/all-v2") else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try id.map { try JSONEncoder().encode(KavitaFilter(library: $0)) }
            ?? Data("{}".utf8)
        return try decode(
            [KavitaSeries].self,
            from: try await sendVersioned(request, path: "Series/all-v2")
        )
    }

    /// The series a server added most recently, newest first, one page at a time.
    ///
    /// The library reads a server through this rather than through ``series(inLibrary:)``:
    /// a server with forty thousand series is minutes of requests and a cache nobody asked
    /// for, and what a reader recognises on opening the app is what arrived last. Android's
    /// `recentSeries` is its twin.
    public func recentSeries(page: Int = 1, size: Int = 20) async throws -> [KavitaSeries] {
        let path = "Series/recently-added-v2"
        guard let url = address.endpoint(path, query: [
            URLQueryItem(name: "pageNumber", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(size)),
        ]) else { throw KavitaError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try decode([KavitaSeries].self, from: try await sendVersioned(request, path: path))
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
