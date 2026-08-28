public import Foundation
public import Catalogue

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
    private let pins: CertificatePins

    /// The session token, held only in memory.
    ///
    /// `kavita-server` requires the app to "manage session tokens without exposing them to
    /// the user". Not persisted either: a token is short-lived, the API key that mints one
    /// is what the secure store holds, and a stale token on disk is one more thing that can
    /// be wrong on a cold launch.
    private var token: String?

    /// What the server said about itself, once it has been asked.
    public private(set) var identity: KavitaIdentity?

    public init(
        address: KavitaAddress,
        pins: CertificatePins = CertificatePins(),
        configuration: URLSessionConfiguration? = nil
    ) {
        self.address = address
        self.pins = pins
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

    /// Lets the session's own queue go when the client does.
    ///
    /// A `URLSession` holds its delegate and an operation queue until it is invalidated,
    /// and neither is released by the client being deallocated. The catalogue client learnt
    /// this the same way: a test run that passed every assertion and then crashed on the
    /// way out.
    deinit {
        session.finishTasksAndInvalidate()
    }

    /// The oldest Kavita this app knows how to talk to.
    ///
    /// `kavita-server` requires the app to reject an older server "naming the required
    /// version", which is a better failure than a series list that is silently empty
    /// because an endpoint moved.
    public static let minimumVersion = KavitaVersion(major: 0, minor: 8, patch: 0)

    /// Authenticates, and reports what the server is.
    ///
    /// Two requests, because they answer two different questions: who am I, and what is
    /// this. A reader whose key works against a server too old to use needs to be told the
    /// second thing, not the first.
    @discardableResult
    public func connect() async throws -> KavitaIdentity {
        let account = try await authenticate()
        let version = try await serverVersion()

        guard version >= Self.minimumVersion else {
            throw KavitaError.serverTooOld(found: version, required: Self.minimumVersion)
        }

        let identity = KavitaIdentity(username: account, version: version)
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

        let data = try await send(request, authenticated: false)
        guard let account = try? JSONDecoder().decode(KavitaAccount.self, from: data) else {
            throw KavitaError.unexpectedResponse
        }
        token = account.token
        return account.username
    }

    private func serverVersion() async throws -> KavitaVersion {
        guard let url = address.endpoint("Server/server-info") else { throw KavitaError.badAddress }
        let data = try await send(URLRequest(url: url))
        guard let info = try? JSONDecoder().decode(KavitaServerInfo.self, from: data),
              let version = KavitaVersion(info.kavitaVersion)
        else { throw KavitaError.unexpectedResponse }
        return version
    }

    /// One request, re-authenticating once if the token has expired.
    ///
    /// `kavita-server`: when a token expires "the app re-authenticates with the stored API
    /// key and retries the request once, without the user seeing an error". Once, not in a
    /// loop: a server that answers 401 to a freshly minted token is saying the key is gone,
    /// and retrying forever would hide that.
    func send(_ request: URLRequest, authenticated: Bool = true) async throws -> Data {
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
            return retried
        }

        if http.statusCode == 401 { throw KavitaError.keyRejected }
        guard (200...299).contains(http.statusCode) else {
            throw KavitaError.http(status: http.statusCode)
        }
        return data
    }
}

/// What a server says it is, once it has answered.
public struct KavitaIdentity: Sendable, Equatable {
    public let username: String
    public let version: KavitaVersion

    public init(username: String, version: KavitaVersion) {
        self.username = username
        self.version = version
    }
}

/// A Kavita version, compared the way versions are compared rather than as a string.
public struct KavitaVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Reads `0.8.3` or `0.8.3.2`, which Kavita has used both of.
    ///
    /// A fourth component is ignored rather than refused: it is a build number, and a
    /// server that reports one is not a server this app should decline to talk to.
    public init?(_ text: String) {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        major = parts[0]
        minor = parts[1]
        patch = parts.count > 2 ? parts[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (left: KavitaVersion, right: KavitaVersion) -> Bool {
        (left.major, left.minor, left.patch) < (right.major, right.minor, right.patch)
    }
}

/// Why a Kavita server did not answer the way it should.
public enum KavitaError: Error, Equatable, Sendable {
    case badAddress
    case unexpectedResponse

    /// The API key is no longer valid. `kavita-server`: the source is marked `unauthorized`
    /// "with an explanation and an action to enter a new key".
    case keyRejected

    /// Older than this app knows how to talk to, named so the reader can act.
    case serverTooOld(found: KavitaVersion, required: KavitaVersion)

    case http(status: Int)
}

/// What `Plugin/authenticate` returns.
struct KavitaAccount: Decodable {
    let username: String
    let token: String
}

/// What `Server/server-info` returns, of what this app reads.
struct KavitaServerInfo: Decodable {
    let kavitaVersion: String
}
