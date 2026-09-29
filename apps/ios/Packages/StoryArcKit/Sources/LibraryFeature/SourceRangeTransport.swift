public import Foundation

public import Catalogue
public import Formats
public import Persistence
public import StoryArcCore

/// The range transport the app registers for a streamed read.
///
/// `offline-downloads`' *Reading while downloading* streams a catalogue's own acquisition
/// address, over the same rules the download queue applies to it: only the configured
/// source's credential travels, only to that source's own origin, and only a certificate
/// the reader trusts opens the connection. `HttpSource`'s default transport
/// (`UrlSessionRangeTransport`) is unauthenticated and unpinned, which answers 401 or fails
/// TLS the moment a catalogue behind either asks for it — `HttpSource.swift:250-253` and
/// `StoryArcApp.swift:115` registered it anyway, because nothing else existed to register.
///
/// `Formats` must not learn what a keychain is, so this lives beside the app's other
/// sources of truth — `LibraryFeature`, which already reads both `Catalogue` and
/// `Persistence` — rather than in `Formats` itself. Android's `SourceRangeTransport` is the
/// same fix.
public struct SourceRangeTransport: RangeTransport {
    private let session: URLSession
    private let sources: @Sendable () -> [Source]
    private let credentials: CredentialStore?

    /// - Parameter pins: the app-wide set — every host a reader has ever pinned, not one
    ///   catalogue's. A streamed read can reach any configured source, so the trust
    ///   delegate has to recognise every one of them, the way ``BackgroundTransfers``' own
    ///   session now does. See dl-core 1.13.
    /// - Parameter sources: read fresh on every fetch, never captured, so a credential
    ///   entered after this transport was registered is found the next time it is asked
    ///   for rather than only after the app relaunches.
    public init(
        pins: CertificatePins,
        credentials: CredentialStore?,
        sources: @escaping @Sendable () -> [Source],
        /// A stub configuration for a test. Nil builds the real ephemeral one below.
        configuration: URLSessionConfiguration? = nil
    ) {
        self.credentials = credentials
        self.sources = sources
        let configuration = configuration ?? {
            let real = URLSessionConfiguration.ephemeral
            // Nothing cached to disk, for the reason `OpdsClient` gives its own session
            // none: a page of a publication is a fragment of a reader's library, and a
            // cache is a copy nobody asked for.
            real.urlCache = nil
            real.requestCachePolicy = .reloadIgnoringLocalCacheData
            return real
        }()
        session = URLSession(
            configuration: configuration,
            delegate: OpdsTrustDelegate(pins: pins),
            delegateQueue: nil
        )
    }

    public func fetch(_ url: URL, from: Int64, through: Int64) async throws -> HttpAnswer {
        guard OpdsOrigin.isFetchable(url) else { throw SourceRangeTransportError.unfetchable }
        let origin = OpdsOrigin(url: url)
        if origin?.downgrades(url) == true { throw SourceRangeTransportError.downgraded }

        var request = URLRequest(url: url)
        request.setValue("bytes=\(from)-\(through)", forHTTPHeaderField: "Range")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let origin, let credential = credential(for: origin), origin.admits(url) {
            request.setValue(credential.header, forHTTPHeaderField: "Authorization")
        }

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SourceError.unreadable }
        return HttpAnswer(
            status: http.statusCode,
            body: body,
            contentRange: http.value(forHTTPHeaderField: "Content-Range"),
            // The trust delegate drops `Authorization` the moment a redirect leaves this
            // origin, the same rule `OpdsRedirect` applies to a feed. `URLSession` still
            // reports where it ended up, which is how `HttpSource` notices it was moved.
            url: http.url ?? url
        )
    }

    /// The credential of the one registered source whose own address is this origin, or
    /// nil when none is — an address the reader typed, or a source with no secret.
    private func credential(for origin: OpdsOrigin) -> OpdsCredential? {
        for candidate in sources() {
            guard let locator = candidate.locator, let home = URL(string: locator),
                  OpdsOrigin(url: home) == origin
            else { continue }
            return candidate.credentialReference
                .flatMap { credentials?.secret(for: $0) }
                .flatMap(OpdsCredential.init(stored:))
        }
        return nil
    }
}

/// Why a range request never left the device.
///
/// Both mean the address is not one this transport will touch at all, before any request is
/// made — the same two refusals ``OpdsClient`` makes of a feed address, restated here because
/// a streamed publication's acquisition link is exactly the same kind of address.
enum SourceRangeTransportError: Error, Equatable {
    /// Not `http` or `https`.
    case unfetchable
    /// `https` stepping down to cleartext.
    case downgraded
}
