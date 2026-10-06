public import Foundation

public import StoryArcCore

/// A cover a title search found, which a reader may accept or ignore.
///
/// `cover-art`: the app "SHALL show the candidates and let the reader choose", and "never
/// silently adopts a match it is not certain of, because a wrong cover is worse than none".
/// So this type is what a search returns — never what a search applies.
public struct CoverCandidate: Sendable, Equatable, Identifiable, Codable {
    /// The title the catalogue holds, which is what a reader compares against their file.
    public let title: String

    /// The author or the year, when the catalogue stated one. Nil rather than an empty
    /// string, so a row draws one line instead of a blank second one.
    public let subtitle: String?

    public let imageURL: URL

    public let provider: CoverTitleProvider

    /// The picture's own address, because two catalogues can answer the same title and a
    /// list needs to draw both.
    public var id: String { imageURL.absoluteString }

    public init(
        title: String, subtitle: String? = nil, imageURL: URL, provider: CoverTitleProvider
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.provider = provider
    }
}

/// How a title is asked about, and how each answer is read.
///
/// Every function here is pure, so the three request shapes and the three response shapes
/// are asserted without a socket. The client below is the only part that needs one.
public enum CoverTitleSearch {
    /// The AniList query, which asks for the one field a candidate needs from each match.
    ///
    /// `perPage: 10` because a reader chooses from a list they can read. A longer list is a
    /// longer scroll through covers that are all nearly right.
    static let aniListQuery = """
    query ($search: String) { Page(perPage: 10) { media(search: $search, type: MANGA) \
    { title { romaji english } coverImage { large } } } }
    """

    /// The request that asks one provider about one title.
    ///
    /// Nil when the title is empty. The author is sent only to Open Library, which is the
    /// only one of the three whose search takes one.
    public static func request(
        _ provider: CoverTitleProvider, title: String, author: String? = nil
    ) -> URLRequest? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch provider {
        case .openLibrary:
            return openLibraryRequest(title: trimmed, author: author)
        case .aniList:
            return jsonPost(
                "https://graphql.anilist.co",
                body: ["query": aniListQuery, "variables": ["search": trimmed]]
            )
        case .mangaUpdates:
            return jsonPost(
                "https://api.mangaupdates.com/v1/series/search",
                body: ["search": trimmed, "perpage": 10]
            )
        }
    }

    private static func openLibraryRequest(title: String, author: String?) -> URLRequest? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        var query = [URLQueryItem(name: "title", value: title)]
        let author = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !author.isEmpty { query.append(URLQueryItem(name: "author", value: author)) }
        query.append(URLQueryItem(name: "limit", value: "10"))
        // Only the three fields a candidate draws. Open Library's default document is large
        // and most of it describes editions nobody here is choosing between.
        query.append(URLQueryItem(name: "fields", value: "title,author_name,cover_i"))
        components?.queryItems = query
        guard let url = components?.plusEscapedURL else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func jsonPost(_ address: String, body: [String: Any]) -> URLRequest? {
        guard let url = URL(string: address),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        return request
    }

    /// The candidates in one provider's answer, or none.
    ///
    /// A malformed answer reads as no candidates rather than as an error: `cover-art` says a
    /// provider that does not answer leaves the publication with the cover it had, and a
    /// provider that answers nonsense has not answered.
    /// What a title search is cached under: the words asked, not the publication asking.
    static func cacheKey(title: String, author: String?, providers: [CoverTitleProvider]) -> String {
        [
            title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            providers.map(\.rawValue).joined(separator: ","),
        ].joined(separator: "|")
    }

    public static func candidates(
        in data: Data, from provider: CoverTitleProvider
    ) -> [CoverCandidate] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        switch provider {
        case .openLibrary: return openLibraryCandidates(object)
        case .aniList: return aniListCandidates(object)
        case .mangaUpdates: return mangaUpdatesCandidates(object)
        }
    }

    private static func openLibraryCandidates(_ object: [String: Any]) -> [CoverCandidate] {
        let documents = object["docs"] as? [[String: Any]] ?? []
        return documents.compactMap { document in
            // A document with no `cover_i` has no picture, so it is not a candidate however
            // well its title matches.
            guard let identifier = document["cover_i"] as? Int,
                  let url = URL(
                      string: "https://covers.openlibrary.org/b/id/\(identifier)-L.jpg"
                  )
            else { return nil }
            return CoverCandidate(
                title: document["title"] as? String ?? "",
                subtitle: (document["author_name"] as? [String])?.first,
                imageURL: url,
                provider: .openLibrary
            )
        }
    }

    private static func aniListCandidates(_ object: [String: Any]) -> [CoverCandidate] {
        let page = (object["data"] as? [String: Any])?["Page"] as? [String: Any]
        let media = page?["media"] as? [[String: Any]] ?? []
        return media.compactMap { entry in
            let titles = entry["title"] as? [String: Any]
            let name = titles?["english"] as? String ?? titles?["romaji"] as? String ?? ""
            guard let cover = entry["coverImage"] as? [String: Any],
                  let address = cover["large"] as? String,
                  let url = URL(string: address)
            else { return nil }
            return CoverCandidate(title: name, imageURL: url, provider: .aniList)
        }
    }

    private static func mangaUpdatesCandidates(_ object: [String: Any]) -> [CoverCandidate] {
        let results = object["results"] as? [[String: Any]] ?? []
        return results.compactMap { result in
            guard let record = result["record"] as? [String: Any],
                  let image = record["image"] as? [String: Any],
                  let addresses = image["url"] as? [String: Any],
                  let address = addresses["original"] as? String,
                  let url = URL(string: address)
            else { return nil }
            return CoverCandidate(
                title: record["title"] as? String ?? "", imageURL: url, provider: .mangaUpdates
            )
        }
    }
}

extension CoverLookupClient {
    /// Candidates for a title, from every provider that answers, for the reader to choose from.
    ///
    /// Not cached, and that is the difference between this and ``cover(for:identifier:)``. An
    /// exact lookup has one answer worth remembering; a title search is a reader looking, and
    /// a reader who looks twice has changed what they are looking for.
    public func candidates(
        title: String,
        author: String? = nil,
        from providers: [CoverTitleProvider] = CoverTitleProvider.allCases
    ) async -> [CoverCandidate] {
        guard isEnabled() else { return [] }
        // Cached like an identifier lookup: `cover-art` asks that the same publication is
        // never looked up twice, and a title search is a lookup.
        let key = CoverTitleSearch.cacheKey(title: title, author: author, providers: providers)
        if let known = await cache.candidates(for: key) { return known }
        var found: [CoverCandidate] = []
        var seen = Set<URL>()
        for provider in providers {
            guard let request = CoverTitleSearch.request(provider, title: title, author: author),
                  let (data, http) = await CoverFetch.send(request, in: session),
                  (200...299).contains(http.statusCode)
            else { continue }
            // A picture is only ever fetched from a listed host, so a candidate elsewhere is
            // one the reader could choose and never see. And one picture is one candidate.
            found += CoverTitleSearch.candidates(in: data, from: provider).filter {
                CoverImageHosts.allows($0.imageURL) && seen.insert($0.imageURL).inserted
            }
        }
        await cache.recordCandidates(found, for: key)
        return found
    }
}
