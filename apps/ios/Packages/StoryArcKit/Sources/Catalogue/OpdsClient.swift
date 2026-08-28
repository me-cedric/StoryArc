public import Foundation

/// How a catalogue is asked who is calling.
///
/// `opds-catalog` requires "HTTP Basic and Bearer tokens". Both are secrets, so this type
/// deliberately has no `description` and is never logged — see ``header``.
public enum OpdsCredential: Sendable, Equatable {
    case basic(user: String, password: String)
    case bearer(token: String)

    /// The credential written as one string, for the secure store.
    ///
    /// Newline-separated and scheme-first. A colon would be ambiguous — a password may
    /// contain one — and something has to say whether the stored secret is a token or a
    /// pair, or a reader signed in with Bearer is sent back as Basic on the next launch.
    public var stored: String {
        switch self {
        case let .basic(user, password): "basic\n\(user)\n\(password)"
        case let .bearer(token): "bearer\n\(token)"
        }
    }

    /// Reads back what ``stored`` wrote.
    ///
    /// Split once for the scheme, then once more for the pair. Splitting on every newline
    /// would truncate a password that contains one, and a password pasted from a manager
    /// can. A user name with a newline in it is not a case anyone has.
    public init?(stored: String) {
        let head = stored.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard head.count == 2, !head[1].isEmpty else { return nil }
        switch head[0] {
        case "basic":
            let pair = head[1].split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            self = .basic(user: String(pair[0]), password: String(pair[1]))
        case "bearer":
            self = .bearer(token: String(head[1]))
        default:
            return nil
        }
    }

    /// The `Authorization` header value.
    ///
    /// Built at the moment of use and not retained, which is the same rule the credential
    /// store follows: `sources` forbids a secret in "preferences, logs, crash reports,
    /// backups, or exported diagnostics", and a value held longer than the request is a
    /// value something else can read.
    var header: String {
        switch self {
        case let .basic(user, password):
            let pair = Data("\(user):\(password)".utf8).base64EncodedString()
            return "Basic \(pair)"
        case let .bearer(token):
            return "Bearer \(token)"
        }
    }
}

/// Fetches OPDS feeds and the files they point at.
///
/// An actor because the trust delegate's refusal has to be read right after the request
/// that caused it, and two concurrent requests to two servers would otherwise race for
/// the same slot.
public actor OpdsClient {
    private let session: URLSession
    private let trust: OpdsTrustDelegate

    public init(pins: CertificatePins = CertificatePins(), configuration: URLSessionConfiguration? = nil) {
        let delegate = OpdsTrustDelegate(pins: pins)
        let configured = configuration ?? {
            let configuration = URLSessionConfiguration.ephemeral
            // Nothing is cached to disk. A catalogue response can name a reader's whole
            // library, and `settings-and-about` promises no data leaves the device that the
            // reader did not send — a URL cache on disk is a copy nobody asked for.
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 20
            configuration.httpAdditionalHeaders = ["Accept": Self.accept]
            return configuration
        }()
        trust = delegate
        session = URLSession(configuration: configured, delegate: delegate, delegateQueue: nil)
    }

    /// Both dialects, and Atom last.
    ///
    /// A server that speaks both should hand over the JSON one — it is the version with a
    /// future — but every server speaks Atom, so it stays in the list rather than being
    /// assumed.
    private static let accept = [
        "application/opds+json",
        "application/atom+xml;profile=opds-catalog",
        "application/atom+xml",
        "*/*;q=0.1",
    ].joined(separator: ", ")

    /// Lets the session's own queue go when the client does.
    ///
    /// A `URLSession` with a delegate holds that delegate and an operation queue until it
    /// is invalidated, and neither is released by the client being deallocated. Left to
    /// itself the app accumulated one session per client — and one client per cover cell,
    /// before this type stopped being made in a loop.
    deinit {
        session.finishTasksAndInvalidate()
    }

    /// One page of a catalogue.
    public func feed(at url: URL, credential: OpdsCredential? = nil) async throws -> OpdsFeed {
        let (data, response) = try await fetch(url, credential: credential)
        return try OpdsDocument.parse(
            data,
            contentType: response.value(forHTTPHeaderField: "Content-Type"),
            // The response URL, not the requested one. A redirect moves what a relative
            // href is relative to, and resolving against the request would point every
            // link on the page at the wrong host.
            baseURL: response.url ?? url
        )
    }

    /// A file the catalogue pointed at — a cover, or a publication being downloaded.
    public func data(at url: URL, credential: OpdsCredential? = nil) async throws -> Data {
        try await fetch(url, credential: credential).data
    }

    /// The certificate refused since this client was last asked.
    ///
    /// Read after a failure, so the UI can show the fingerprint and offer to pin it. Nil
    /// when the failure was something else, which is what stops a network timeout from
    /// being presented as a certificate question.
    public func lastRefusedCertificate() -> UntrustedCertificate? {
        trust.takeRefusal()
    }

    private func fetch(
        _ url: URL,
        credential: OpdsCredential?
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: url)
        if let credential { request.setValue(credential.header, forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // A cancelled challenge arrives here. If it was the trust delegate that
            // cancelled, the certificate is the story and the `URLError` is not.
            if let refused = trust.takeRefusal() {
                throw OpdsRefusal.untrusted(refused)
            }
            throw error
        }

        guard let http = response as? HTTPURLResponse else { throw OpdsError.empty }

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            // Which scheme, so the prompt can ask for the right thing. A server that wants
            // a token and is handed a username fails in a way that looks like a wrong
            // password.
            throw OpdsError.unauthorized(
                scheme: http.value(forHTTPHeaderField: "WWW-Authenticate")
                    .flatMap(OpdsError.AuthenticationScheme.init(challenge:))
            )
        default:
            throw OpdsError.http(status: http.statusCode)
        }
    }
}

/// A refusal that carries what was refused.
///
/// Separate from ``OpdsError`` because it is not a parsing outcome and not an HTTP status:
/// it is a decision this app made, and the reader can reverse it.
public enum OpdsRefusal: Error, Equatable, Sendable {
    case untrusted(UntrustedCertificate)
}
