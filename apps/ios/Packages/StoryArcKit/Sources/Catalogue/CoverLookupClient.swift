public import Foundation

public import StoryArcCore

/// Asks an open catalogue where one publication's cover is, when the reader has said it may.
///
/// Three rules shape every method here, and all three are `cover-art` requirements rather
/// than taste:
///
/// 1. **Nothing is asked while the setting is off.** The gate is the first statement of
///    ``cover(for:identifier:)``, before a URL is even built, so there is no path through
///    this type that reaches the network without it.
/// 2. **One request per publication.** The cache is consulted first and written after, and a
///    recorded refusal counts as an answer.
/// 3. **A refusal is quiet.** Nothing throws. A reader who did not ask for this cover is
///    shown no error about it, and nothing retries.
public actor CoverLookupClient {
    /// Whether the reader has turned the lookup on, read at the moment of use.
    ///
    /// A closure rather than a stored `Bool`: the setting can change while the app runs, and
    /// a copy taken at `init` would let a reader switch the lookup off and still be asked
    /// about by whichever client was already made.
    let isEnabled: @Sendable () -> Bool

    private let cache: CoverLookupCache
    let session: URLSession

    public init(
        isEnabled: @escaping @Sendable () -> Bool,
        cache: CoverLookupCache = CoverLookupCache(),
        configuration: URLSessionConfiguration? = nil
    ) {
        self.isEnabled = isEnabled
        self.cache = cache
        let configured = configuration ?? {
            let configuration = URLSessionConfiguration.ephemeral
            // Nothing cached by the loader: this type keeps its own record of every answer,
            // and a second cache with a different lifetime would re-ask a provider that the
            // first one had already decided was done with.
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 15
            return configuration
        }()
        session = URLSession(configuration: configured)
    }

    /// Lets the session's own queue go when the client does, as the catalogue client must.
    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Where this publication's cover is, or nil.
    ///
    /// `key` identifies the publication for the cache only. It never travels: the request is
    /// built from `identifier` and from nothing else, which is what `cover-art` means by
    /// "no library listing, no reading history, no device identifier".
    public func cover(for key: String, identifier: CoverIdentifier) async -> URL? {
        guard isEnabled() else { return nil }
        if let known = await cache.answer(for: key) { return known.imageURL }
        guard let url = CoverLookupRequest.url(for: identifier) else { return nil }

        let found = await ask(url, provider: identifier.provider)
        await cache.record(
            CoverLookupAnswer(provider: identifier.provider, imageURL: found), for: key
        )
        return found
    }

    /// One request, and whatever it answers.
    ///
    /// A 403, a 404, a 429 or a thrown error all come back as nil. They are different
    /// reasons for the same outcome — this publication keeps the cover it had — and telling
    /// them apart here would only create somewhere for a retry to be added later.
    private func ask(_ url: URL, provider: CoverLookupProvider) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            provider.answersWithImage ? "image/*" : "application/json",
            forHTTPHeaderField: "Accept"
        )

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return nil }

        // Both image providers answer the picture at the address that was asked for, after
        // whatever redirects they use. The URL the session ended on is the one to keep: the
        // Cover Art Archive's front route is a redirect to an Internet Archive file, and
        // storing the redirect rather than its target would ask twice on every read.
        if provider.answersWithImage { return http.url ?? url }
        return Self.imageURL(inBookDocument: data)
    }

    /// The `image` field of an Audnexus book document.
    ///
    /// The one provider that answers with a document rather than a picture. Parsed with no
    /// model type because one field is wanted: a struct would state nine more and break the
    /// day the service adds a tenth.
    static func imageURL(inBookDocument data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let image = object["image"] as? String
        else { return nil }
        return URL(string: image)
    }
}
