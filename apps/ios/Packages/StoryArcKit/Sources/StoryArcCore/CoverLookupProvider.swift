public import Foundation

/// An identifier a publication carries that some open catalogue can answer with a cover.
///
/// Three cases, because three keyless providers exist and each answers one of them. A
/// fourth identifier with no provider behind it would be a value nothing can use, so the
/// enum and the provider list are deliberately the same length.
public enum CoverIdentifier: Sendable, Equatable, Hashable {
    /// A book's ISBN, as an EPUB's OPF states it. Ten or thirteen digits, no hyphens.
    case isbn(String)

    /// A MusicBrainz release-group id, which an audiobook ripped from CDs often carries.
    case musicBrainzReleaseGroup(String)

    /// An Audible ASIN, which an Audible-sourced audiobook carries.
    case audibleASIN(String)

    /// The provider this identifier belongs to.
    ///
    /// A property rather than a lookup table: the pairing is one to one, and it is the whole
    /// reason the identifier is modelled at all.
    public var provider: CoverLookupProvider {
        switch self {
        case .isbn: .openLibrary
        case .musicBrainzReleaseGroup: .coverArtArchive
        case .audibleASIN: .audnexus
        }
    }

    /// The identifier's own characters, which is the whole of what leaves the device.
    ///
    /// `cover-art` says a lookup "sends the identifier and nothing else: no library listing,
    /// no reading history, no device identifier". This property is what a test asserts that
    /// against, because the request is built from it and from nothing else.
    public var value: String {
        switch self {
        case let .isbn(value): value
        case let .musicBrainzReleaseGroup(value): value
        case let .audibleASIN(value): value
        }
    }
}

extension CoverIdentifier {
    /// Reads an ISBN a file stated, or refuses it.
    ///
    /// Hyphens and spaces are how an OPF usually writes one, and they are not part of the
    /// number. Everything else is refused here rather than at the provider: a malformed
    /// identifier in a URL is a request that can only fail, and `cover-art` allows one
    /// request per publication, so a wasted one is the only one that publication gets.
    public static func isbn(reading text: String) -> CoverIdentifier? {
        let digits = text.filter { !$0.isWhitespace && $0 != "-" }.uppercased()
        guard digits.count == 10 || digits.count == 13 else { return nil }
        guard digits.dropLast().allSatisfy(\.isNumber) else { return nil }
        guard let check = digits.last else { return nil }
        guard check.isNumber || (digits.count == 10 && check == "X") else { return nil }
        return .isbn(digits)
    }

    /// Reads a MusicBrainz release-group id, which is a UUID and nothing else.
    public static func musicBrainz(reading text: String) -> CoverIdentifier? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return .musicBrainzReleaseGroup(trimmed.lowercased())
    }

    /// Reads an Audible ASIN: ten characters, letters and digits, as Audible mints them.
    public static func asin(reading text: String) -> CoverIdentifier? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 10, trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return .audibleASIN(trimmed)
    }
}

/// An open catalogue StoryArc may ask for a cover, once a reader turns the lookup on.
///
/// All three need no API key and no owner account, which is what keeps this feature from
/// becoming a task for whoever runs the server. `design.md` records why Google Books is not
/// here: it needs a key the owner must create, and its terms put another brand on
/// StoryArc's publication page.
public enum CoverLookupProvider: String, Sendable, Equatable, CaseIterable, Codable {
    case openLibrary
    case coverArtArchive
    case audnexus

    /// The name the setting shows, so a reader reads who would be asked before they agree.
    ///
    /// Not localised: these are the catalogues' own names, and translating a proper noun
    /// would stop a reader recognising the service they are being told about.
    public var displayName: String {
        switch self {
        case .openLibrary: "Open Library"
        case .coverArtArchive: "Cover Art Archive"
        case .audnexus: "Audnexus"
        }
    }

    /// The host a request to this provider reaches.
    ///
    /// The other half of what the setting states: a reader reads the name and can see the
    /// address it resolves to.
    public var host: String {
        switch self {
        case .openLibrary: "covers.openlibrary.org"
        case .coverArtArchive: "coverartarchive.org"
        case .audnexus: "api.audnex.us"
        }
    }

    /// Whether the answer is the picture itself or a document that names where it is.
    ///
    /// Open Library and the Cover Art Archive answer with the image. Audnexus answers with
    /// a book document whose `image` field holds the address. One property decides it, so
    /// the client keeps one code path instead of three.
    public var answersWithImage: Bool {
        self != .audnexus
    }
}

/// Where one identifier is asked about, and nowhere else.
public enum CoverLookupRequest {
    /// The single URL this identifier is looked up at.
    ///
    /// `default=false` on Open Library matters. Without it the service answers a blank
    /// placeholder with status 200, and the app would store a grey rectangle as the
    /// reader's cover and never ask again.
    public static func url(for identifier: CoverIdentifier) -> URL? {
        switch identifier {
        case let .isbn(value):
            URL(string: "https://covers.openlibrary.org/b/isbn/\(value)-L.jpg?default=false")
        case let .musicBrainzReleaseGroup(value):
            URL(string: "https://coverartarchive.org/release-group/\(value)/front")
        case let .audibleASIN(value):
            URL(string: "https://api.audnex.us/books/\(value)")
        }
    }
}

/// The hosts a cover lookup may reach: the providers the setting names, and the hosts their
/// pictures live on.
///
/// `AGENTS.md` non-negotiable 2: data leaves the device only to sources the user configured.
/// Turning the lookup on is that configuration, and the row names these providers. A redirect
/// or an answer can name any address at all, so every request and every redirect is checked
/// here before it is made — not after, when the request has already left. Android's
/// `CoverImageHosts` holds the same list.
public enum CoverImageHosts {

    /// Each entry admits itself and its subdomains.
    public static let suffixes = [
        // Open Library: the search, the covers, and the archive its covers redirect to.
        "openlibrary.org",
        "archive.org",
        // Cover Art Archive, which redirects to the same archive.
        "coverartarchive.org",
        // Audnexus, and the store its `image` field points at.
        "audnex.us",
        "media-amazon.com",
        "ssl-images-amazon.com",
        // AniList's API and its picture host.
        "anilist.co",
        // MangaUpdates' API and its picture host.
        "mangaupdates.com",
    ]

    /// Whether `url` is https and on a listed host.
    public static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              var host = url.host?.lowercased()
        else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return suffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

extension URLComponents {
    /// The query with `+` escaped. `URLQueryItem` leaves a `+` as it is, and every server
    /// these requests reach reads a bare `+` in a query as a space — so "C++" was searched
    /// as "C  ".
    public var plusEscapedURL: URL? {
        var copy = self
        copy.percentEncodedQuery = copy.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return copy.url
    }
}

/// A keyless catalogue that answers a title with candidates.
///
/// Separate from ``CoverLookupProvider`` because these answer a question with several
/// answers and that one answers a question with one. Joining them would give the exact
/// lookup a "which of these did you mean" that it never has.
public enum CoverTitleProvider: String, Sendable, Equatable, CaseIterable, Codable {
    /// Books, by title and author.
    case openLibrary

    /// Manga and anime. Keyless, and the one most likely to know a volume by its series.
    case aniList

    /// Manga, including many series AniList has no entry for.
    case mangaUpdates

    public var displayName: String {
        switch self {
        case .openLibrary: "Open Library"
        case .aniList: "AniList"
        case .mangaUpdates: "MangaUpdates"
        }
    }

    public var host: String {
        switch self {
        case .openLibrary: "openlibrary.org"
        case .aniList: "graphql.anilist.co"
        case .mangaUpdates: "api.mangaupdates.com"
        }
    }
}

/// Every service the cover-lookup switch lets the app ask, by the name a reader knows it by.
///
/// Both lists, because one switch gates both: the identifier lookup and the title search.
/// `cover-art` requires the app to name a provider before it asks one, so the switch's row is
/// built from this, and a provider added to either list appears on that row by construction.
public let coverLookupServiceNames: [String] = {
    var seen = Set<String>()
    return (CoverLookupProvider.allCases.map(\.displayName) + CoverTitleProvider.allCases.map(\.displayName))
        .filter { seen.insert($0).inserted }
}()
