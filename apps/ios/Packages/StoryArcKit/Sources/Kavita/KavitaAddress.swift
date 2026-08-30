public import Foundation

/// Where a Kavita server is and how to prove who you are.
///
/// `kavita-server` takes "a base URL and a user API key". Both are needed for every
/// request, and neither is useful alone, so they travel together.
public struct KavitaAddress: Sendable, Equatable {
    /// The server's root — `https://kavita.example`, with no `/api` and no trailing slash.
    public let base: URL

    /// The reader's own API key, from Kavita's user settings.
    public let apiKey: String

    public init(base: URL, apiKey: String) {
        self.base = base
        self.apiKey = apiKey
    }

    /// Reads an address out of whatever the reader pasted.
    ///
    /// `kavita-server`: when a reader pastes "a Kavita OPDS URL that embeds the API key",
    /// the app "extracts the base URL and key and configures a native Kavita source rather
    /// than a generic OPDS source". Kavita's OPDS URL is
    /// `https://host/api/opds/<key>`, and that key is the same one its settings screen
    /// shows — so the paste a reader is most likely to have to hand already contains
    /// everything, and asking them to take it apart by hand would be asking them to do
    /// work the app can do.
    ///
    /// Returns `nil` for a URL that is not one of Kavita's, which is what lets the caller
    /// fall back to asking for the two pieces separately.
    public static func fromOpds(_ pasted: String) -> KavitaAddress? {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              url.host() != nil
        else { return nil }

        // The path is `…/api/opds/<key>`, possibly with a prefix if Kavita sits behind a
        // reverse proxy at a subpath. Found by looking for the marker rather than by
        // counting components, because the prefix can be any depth.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let opds = parts.firstIndex(of: "opds"), opds > 0, parts[opds - 1] == "api",
              opds + 1 < parts.count
        else { return nil }

        let key = parts[opds + 1]
        guard !key.isEmpty else { return nil }

        var base = URLComponents()
        base.scheme = url.scheme
        base.host = url.host()
        base.port = url.port
        // Everything before `api`, which is the reverse-proxy prefix when there is one.
        let prefix = parts[..<(opds - 1)]
        base.path = prefix.isEmpty ? "" : "/" + prefix.joined(separator: "/")

        guard let root = base.url else { return nil }
        return KavitaAddress(base: root, apiKey: key)
    }

    /// An address from a base URL a reader typed and a key they pasted separately.
    ///
    /// Trailing slashes and a pasted `/api` are removed rather than refused: both are
    /// things a reader copies out of a browser bar, and neither is a mistake worth an
    /// error message.
    public static func from(base typed: String, apiKey: String) -> KavitaAddress? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmed.isEmpty else { return nil }

        let completed = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: completed), components.host?.isEmpty == false
        else { return nil }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/api") { path.removeLast(4) }
        components.path = path
        components.query = nil
        components.fragment = nil

        guard let base = components.url else { return nil }
        return KavitaAddress(base: base, apiKey: trimmedKey)
    }

    /// One of Kavita's endpoints, relative to the base.
    func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(
            url: base.appending(path: "api").appending(path: path),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }

    /// Where one chapter's bytes come from.
    ///
    /// Public where ``endpoint(_:query:)`` is not, because a download record has to remember
    /// where it came from — `offline-downloads` retries from it without re-browsing. It is
    /// safe to write down: Kavita takes the key as a bearer header on this route, so the URL
    /// is a path and a chapter number and carries no secret. An OPDS acquisition link, which
    /// can embed one, is the reason that distinction is worth making out loud.
    public func chapterURL(_ chapterId: Int) -> URL? {
        endpoint("Download/chapter", query: [
            URLQueryItem(name: "chapterId", value: String(chapterId)),
        ])
    }
}
