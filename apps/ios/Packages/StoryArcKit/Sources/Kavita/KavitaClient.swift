public import Foundation

/// A Kavita server, and what StoryArc asks it.
///
/// Kavita already speaks OPDS, and a reader can add one as a catalogue today. This exists
/// because, as the spec puts it, "OPDS cannot express collections, reading lists, per-page
/// progress, or the 'want to read' state" — the difference between browsing a Kavita server
/// and being a Kavita client.
///
/// **Built against Kavita's documented API and a mock of it, not against a live server.**
/// Nobody here has one. The shapes below are what the documentation describes; the first
/// person to point this at a real Kavita should expect to correct something, and the mock in
/// `scripts/kavita-server.mjs` is where a correction gets recorded.
public actor KavitaClient {
    public let address: KavitaAddress

    private let session: URLSession

    /// The session token, held only in memory.
    ///
    /// `kavita-server` requires the app to "manage session tokens without exposing them to
    /// the user". Not persisted either: a token is short-lived, the API key that mints one
    /// is what the secure store holds, and a stale token on disk is one more thing that can
    /// be wrong on a cold launch.
    private var token: String?

    /// What the server said about itself, once it has been asked.
    public private(set) var identity: KavitaIdentity?

    /// No `pins`, and no trust delegate.
    ///
    /// It used to take a `CertificatePins` and store it, and nothing ever read it: the
    /// session below is built with no delegate, so there was no `urlSession(_:didReceive:)`
    /// hook for a pin to reach. Rank 15 of the 30 August security review — a parameter that
    /// claims a defence it does not provide is worse than an absent one, because the next
    /// change weakens the delegate rather than wiring it. Kavita therefore needs a
    /// certificate the system already trusts, and the sources screen says so plainly.
    public init(
        address: KavitaAddress,
        configuration: URLSessionConfiguration? = nil
    ) {
        self.address = address
        let configured = configuration ?? {
            let configuration = URLSessionConfiguration.ephemeral
            // Nothing cached to disk, for the reason the catalogue client gives: a response
            // can name a reader's whole library.
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 20
            return configuration
        }()
        session = URLSession(configuration: configured)
    }

    /// One GET against an endpoint, as bytes.
    public func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard let url = address.endpoint(path, query: query) else { throw KavitaError.badAddress }
        return try await send(URLRequest(url: url))
    }

    /// The routes this server has answered 404 to, so the discovery is paid for once.
    ///
    /// Held here because this actor is one server. It lives for the session and no longer:
    /// the answer is cheap to find again, and the registry of saved sources is a place for
    /// what a reader chose rather than for what a server happened to answer.
    private var unsupported: Set<String> = []

    /// Sends a request to a route an older Kavita may not have, and remembers a 404.
    ///
    /// **A client cannot ask a Kavita what version it is.** Measured on 2026-09-06:
    /// `/api/Server/version`, `/api/Health/api-version` and `/api/Server/accepting-connections`
    /// all answer 404, `/api/Server/server-info-slim` is admin-only, and swagger is off in
    /// production. So feature detection is the only detection there is, and the feature is
    /// the route answering at all.
    ///
    /// **Only a 404 counts.** A 401, a 403, a 500 or a timeout is the key or the server being
    /// wrong for a moment, and reading one of those as "old server" would turn one expired
    /// token into a permanent downgrade that no later good answer could undo. A 404 from the
    /// token route is not counted either: `authenticate` names that route before it travels.
    ///
    /// **There is no older shape to fall back to.** No documented v1 of these routes was
    /// found, and Kavita's controllers carry no `[Obsolete]` marker naming one. Inventing a
    /// request shape would be a guess a reader pays for, so this refuses in a sentence the
    /// screens can draw instead.
    func sendVersioned(_ request: URLRequest, path: String) async throws -> Data {
        guard !unsupported.contains(path) else { throw KavitaError.routeMissing(path: path) }
        do {
            return try await send(request)
        } catch KavitaError.http(status: 404) {
            unsupported.insert(path)
            throw KavitaError.routeMissing(path: path)
        }
    }

    /// Lets the session's own queue go when the client does.
    ///
    /// A `URLSession` holds its delegate and an operation queue until it is invalidated,
    /// and neither is released by the client being deallocated. The catalogue client learnt
    /// this the same way: a test run that passed every assertion and then crashed on the
    /// way out.
    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Authenticates, and stops.
    ///
    /// One request, because the server answers only one question a plugin may ask: who is
    /// this key. This used to ask a second, `Server/server-info`, to gate the server on a
    /// minimum version. That route is in no shipped Kavita -- absent from the published
    /// `openapi.json` of v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4, and 404 on a live
    /// 0.9.1.4 -- so the 404 threw and **adding a Kavita source failed for every reader on
    /// every version**. The gate it fed could never fire for the same reason.
    ///
    /// The gate was deleted rather than repaired on 2026-09-07, because nothing can feed
    /// it and nothing would use it. No route states the version: `Server/version`,
    /// `Health/api-version` and `Server/accepting-connections` all 404,
    /// `Server/server-info-slim` is admin only, swagger is off in production, and
    /// `Health` answers `Ok` with no version in it. And the verbs of every route either
    /// client calls are identical across those five releases, which is April 2025 to
    /// September 2026, so a version number would decide nothing.
    ///
    /// What replaces it is feature detection, which was already here:
    /// ``sendVersioned(_:path:)`` reads a 404 on a listing route as that route missing,
    /// remembers it for the session, and says so in a sentence.
    @discardableResult
    public func connect() async throws -> KavitaIdentity {
        let identity = KavitaIdentity(username: try await authenticate())
        self.identity = identity
        return identity
    }

    /// Exchanges the API key for a session token.
    private func authenticate() async throws -> String {
        guard let url = address.endpoint(
            "Plugin/authenticate",
            query: [
                URLQueryItem(name: "apiKey", value: address.apiKey),
                URLQueryItem(name: "pluginName", value: "StoryArc"),
            ]
        ) else { throw KavitaError.badAddress }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // A 404 here is this route missing, not whichever route the caller wanted. Letting it
        // travel outwards lets `sendVersioned` record it against a listing the reader never
        // reached, and that listing then refuses for the rest of the session.
        let data: Data
        do {
            data = try await send(request, authenticated: false)
        } catch KavitaError.http(status: 404) {
            throw KavitaError.routeMissing(path: "Plugin/authenticate")
        }
        guard let account = try? JSONDecoder().decode(KavitaAccount.self, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        token = account.token
        return account.username
    }

    /// One request, re-authenticating once if the token has expired.
    ///
    /// `kavita-server`: when a token expires "the app re-authenticates with the stored API
    /// key and retries the request once, without the user seeing an error". Once, not in a
    /// loop: a server that answers 401 to a freshly minted token is saying the key is gone,
    /// and retrying forever would hide that.
    func send(
        _ request: URLRequest,
        authenticated: Bool = true,
        onType: ((String?) -> Void)? = nil
    ) async throws -> Data {
        var attempt = request
        if authenticated {
            if token == nil { _ = try await authenticate() }
            attempt.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        }
        attempt.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: attempt)
        guard let http = response as? HTTPURLResponse else { throw KavitaError.unexpectedResponse }

        if http.statusCode == 401, authenticated {
            token = nil
            _ = try await authenticate()
            var retry = request
            retry.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
            retry.setValue("application/json", forHTTPHeaderField: "Accept")
            let (retried, retriedResponse) = try await session.data(for: retry)
            guard let http = retriedResponse as? HTTPURLResponse else {
                throw KavitaError.unexpectedResponse
            }
            // Still refused after a fresh token: the key itself is no longer valid.
            guard http.statusCode != 401 else { throw KavitaError.keyRejected }
            guard (200...299).contains(http.statusCode) else {
                throw KavitaError.http(status: http.statusCode)
            }
            onType?(http.value(forHTTPHeaderField: "Content-Type")?
                .components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces))
            return retried
        }

        if http.statusCode == 401 { throw KavitaError.keyRejected }
        guard (200...299).contains(http.statusCode) else {
            throw KavitaError.http(status: http.statusCode)
        }
        onType?(http.value(forHTTPHeaderField: "Content-Type")?
            .components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces))
        return data
    }
}

/// Who the reader is on this server, which is all authentication answers with.
///
/// It held a version until 2026-09-07. Nothing could fill that field: no route on any
/// shipped Kavita states the server's version to a plugin. See ``KavitaClient/connect()``.
public struct KavitaIdentity: Sendable, Equatable {
    public let username: String

    public init(username: String) {
        self.username = username
    }
}

/// Why a Kavita server did not answer the way it should.
public enum KavitaError: Error, Equatable, Sendable {
    case badAddress
    case unexpectedResponse

    /// The API key is no longer valid. `kavita-server`: the source is marked `unauthorized`
    /// "with an explanation and an action to enter a new key".
    case keyRejected

    /// The server does not have this route, so it is an older Kavita than this app can use.
    ///
    /// The only signal there is. Nothing states a version: see ``KavitaClient/connect()``
    /// and ``KavitaClient/sendVersioned(_:path:)``.
    case routeMissing(path: String)

    case http(status: Int)
}

/// What `Plugin/authenticate` returns.
struct KavitaAccount: Decodable {
    let username: String
    let token: String
}
