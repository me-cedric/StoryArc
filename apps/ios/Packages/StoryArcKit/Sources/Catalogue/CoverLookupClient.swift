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

    let cache: CoverLookupCache
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
        await lookUp(key, identifier)?.url
    }

    /// The looked-up cover's picture, or nil. One call for the ladder: the lookup, then the
    /// picture. An image provider already answered with the picture, so it is not asked twice.
    /// A picture that does not come is recorded as a refusal, so a shelf that draws this cover
    /// again asks nothing.
    public func coverImage(for key: String, identifier: CoverIdentifier) async -> Data? {
        guard let found = await lookUp(key, identifier) else { return nil }
        if let kept = await cache.picture(for: key) { return kept }
        var fetched = found.picture
        if fetched == nil { fetched = await image(at: found.url) }
        guard let picture = fetched, !picture.isEmpty else {
            await cache.record(
                CoverLookupAnswer(provider: identifier.provider, imageURL: nil), for: key
            )
            return nil
        }
        await cache.recordPicture(picture, for: key)
        return picture
    }

    /// The picture at `url`, or nil. Only behind the setting, only from a listed host, and
    /// never more than ``CoverFetch/maxBytes``.
    public func image(at url: URL) async -> Data? {
        guard isEnabled(), CoverImageHosts.allows(url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, http) = await CoverFetch.send(request, in: session),
              (200...299).contains(http.statusCode), !data.isEmpty
        else { return nil }
        return data
    }

    private struct Found {
        let url: URL
        let picture: Data?
    }

    private func lookUp(_ key: String, _ identifier: CoverIdentifier) async -> Found? {
        guard isEnabled() else { return nil }
        if let known = await cache.answer(for: key) {
            return known.imageURL.map { Found(url: $0, picture: nil) }
        }
        guard let url = CoverLookupRequest.url(for: identifier) else { return nil }
        let found = await ask(url, provider: identifier.provider)
        await cache.record(
            CoverLookupAnswer(provider: identifier.provider, imageURL: found?.url), for: key
        )
        return found
    }

    private func ask(_ url: URL, provider: CoverLookupProvider) async -> Found? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            provider.answersWithImage ? "image/*" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        guard let (data, http) = await CoverFetch.send(request, in: session),
              (200...299).contains(http.statusCode)
        else { return nil }
        // Both image providers answer the picture at the address that was asked for, after
        // whatever redirects they use. The address the transport ended on is the one to
        // keep: the Cover Art Archive's front route is a redirect to an Internet Archive
        // file, and storing the redirect rather than its target would ask twice on every read.
        if provider.answersWithImage {
            return data.isEmpty ? nil : Found(url: http.url ?? url, picture: data)
        }
        return Self.imageURL(inBookDocument: data).map { Found(url: $0, picture: nil) }
    }

    /// The `image` field of an Audnexus book document, where it is a listed https address.
    static func imageURL(inBookDocument data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let image = object["image"] as? String,
              let url = URL(string: image), CoverImageHosts.allows(url)
        else { return nil }
        return url
    }
}
