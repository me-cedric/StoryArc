import Foundation
import Testing

@testable import Kavita

/// The connection requirement, against a stubbed transport.
struct KavitaClientTests {
    /// A client on a host nothing else is using, so these tests can run beside others.
    private func client(
        _ answer: @escaping @Sendable (URLRequest) -> KavitaStub.Answer
    ) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host, answer: answer)
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "key"))
        return KavitaClient(address: address, configuration: configuration)
    }

    private func json(_ text: String) -> KavitaStub.Answer {
        .response(status: 200, body: Data(text.utf8))
    }

    @Test("Connecting authenticates and reports the account and version")
    func connects() async throws {
        let client = try client { request in
            if request.url?.path().contains("authenticate") == true {
                return self.json(#"{"username":"ada","token":"t","apiKey":"key"}"#)
            }
            return self.json(#"{"kavitaVersion":"0.8.3"}"#)
        }
        let identity = try await client.connect()
        #expect(identity.username == "ada")
        #expect(identity.version == KavitaVersion(major: 0, minor: 8, patch: 3))
    }

    @Test("A server older than the minimum is refused, naming the version")
    func refusesAnOldServer() async throws {
        // `kavita-server` requires the app to reject an older server "naming the required
        // version", which is a better failure than a series list that is silently empty.
        let client = try client { request in
            if request.url?.path().contains("authenticate") == true {
                return self.json(#"{"username":"ada","token":"t","apiKey":"key"}"#)
            }
            return self.json(#"{"kavitaVersion":"0.7.14"}"#)
        }
        await #expect(
            throws: KavitaError.serverTooOld(
                found: KavitaVersion(major: 0, minor: 7, patch: 14),
                required: KavitaClient.minimumVersion
            )
        ) {
            try await client.connect()
        }
    }

    @Test("A build number in the version is ignored rather than refused")
    func fourComponentVersion() async throws {
        let client = try client { request in
            if request.url?.path().contains("authenticate") == true {
                return self.json(#"{"username":"ada","token":"t","apiKey":"key"}"#)
            }
            return self.json(#"{"kavitaVersion":"0.8.3.2"}"#)
        }
        #expect(try await client.connect().version == KavitaVersion(major: 0, minor: 8, patch: 3))
    }

    @Test("An expired token is renewed and the request retried once")
    func renewsAnExpiredToken() async throws {
        // `kavita-server`: the app "re-authenticates with the stored API key and retries the
        // request once, without the user seeing an error".
        let calls = Counter()
        let client = try client { request in
            let path = request.url?.path() ?? ""
            if path.contains("authenticate") {
                return self.json(#"{"username":"ada","token":"fresh","apiKey":"key"}"#)
            }
            if path.contains("server-info") {
                return self.json(#"{"kavitaVersion":"0.8.3"}"#)
            }
            // The first call with a token fails as though it had expired; the second, with
            // the token minted after that, succeeds.
            calls.value += 1
            return calls.value == 1
                ? .response(status: 401, body: Data())
                : self.json(#"{"ok":true}"#)
        }
        try await client.connect()
        let data = try await client.get("Library/libraries")
        #expect(String(bytes: data, encoding: .utf8) == #"{"ok":true}"#)
        #expect(calls.value == 2)
    }

    @Test("A key that is no longer valid is named as such")
    func keyRejected() async throws {
        // `kavita-server`: the source is marked unauthorized "with an explanation and an
        // action to enter a new key". Retrying for ever would hide that.
        let client = try client { request in
            request.url?.path().contains("authenticate") == true
                ? self.json(#"{"username":"ada","token":"t","apiKey":"key"}"#)
                : .response(status: 401, body: Data())
        }
        await #expect(throws: KavitaError.keyRejected) {
            _ = try await client.get("Library/libraries")
        }
    }

    @Test("A reported position posts Kavita's whole chain, at the page the reader is on")
    func reportsAPosition() async throws {
        // The push half of `reading-progress`, on the wire. `scripts/kavita-server.mjs
        // --self-test` asserts the server's half of the same number: a `pageNum` of 7 is
        // eight pages read, and eight pages read is page 7 again.
        let sent = KavitaSent()
        let client = try client { request in
            if request.url?.path().contains("authenticate") == true {
                return self.json(#"{"username":"ada","token":"t","apiKey":"key"}"#)
            }
            sent.record(request)
            return self.json("{}")
        }

        try await client.report(
            KavitaPosition(libraryId: 1, seriesId: 11, volumeId: 1100, chapterId: 12, pageNum: 7)
        )

        let request = try #require(sent.request)
        #expect(request.url?.path() == "/api/Reader/progress")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        // The key rides in that header and never in the URL, which a proxy would log.
        #expect(request.url?.query() == nil)

        let posted = try JSONDecoder().decode(KavitaPosition.self, from: try #require(sent.body))
        #expect(posted == KavitaPosition(
            libraryId: 1, seriesId: 11, volumeId: 1100, chapterId: 12, pageNum: 7
        ))
    }

    @Test("Marking a chapter read names the series as well as the chapter")
    func marksAChapter() async throws {
        let sent = KavitaSent()
        let client = try client { request in
            if request.url?.path().contains("authenticate") == true {
                return self.json(#"{"username":"ada","token":"t","apiKey":"key"}"#)
            }
            sent.record(request)
            return self.json("{}")
        }

        try await client.mark(seriesId: 11, chapterId: 12, isRead: false)

        let request = try #require(sent.request)
        #expect(request.url?.path() == "/api/Reader/mark-chapter-unread")
        let body = try #require(sent.body)
        let text = try #require(String(bytes: body, encoding: .utf8))
        #expect(text.contains("\"seriesId\":11") && text.contains("\"chapterId\":12"))
    }

    /// A box, because the stub runs on the session's queue.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }
}

/// What the transport was asked, so a test can assert on the request and not only the answer.
///
/// `URLProtocol` hands a body over as a stream rather than as `httpBody`, and the stream can
/// be read once — so it is drained the moment the request arrives.
final class KavitaSent: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: URLRequest?
    private var payload: Data?

    func record(_ request: URLRequest) {
        let body = request.httpBody ?? Self.drain(request.httpBodyStream)
        lock.withLock {
            seen = request
            payload = body
        }
    }

    var request: URLRequest? { lock.withLock { seen } }
    var body: Data? { lock.withLock { payload } }

    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(contentsOf: buffer[..<read])
        }
        return data
    }
}

/// A transport that answers from a closure, one per host.
///
/// Keyed by host rather than a single global answer. `.serialized` orders the tests *within*
/// a suite and nothing between two suites, so two suites sharing one closure set each
/// other's answers — which is what happened, and what made half of these tests report the
/// other half's responses.
final class KavitaStub: URLProtocol {
    enum Answer {
        case response(status: Int, body: Data)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: @Sendable (URLRequest) -> Answer] = [:]

    /// Registers an answer for a host of its own, and returns a session that uses it.
    static func session(
        host: String,
        answer: @escaping @Sendable (URLRequest) -> Answer
    ) -> URLSessionConfiguration {
        lock.withLock { answers[host] = answer }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KavitaStub.self]
        return configuration
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let host = url.host(),
              let answer = Self.lock.withLock({ Self.answers[host] })?(request),
              case let .response(status, body) = answer,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
