import Foundation
import Testing

@testable import Kavita

/// The connection requirement, against a stubbed transport.
///
/// Serialised, because the stub is registered process-wide.
@Suite(.serialized)
struct KavitaClientTests {
    private func client(
        _ answer: @escaping @Sendable (URLRequest) -> KavitaStub.Answer
    ) throws -> KavitaClient {
        KavitaStub.answer = answer
        KavitaStub.seen = []
        let address = try #require(
            KavitaAddress.from(base: "https://kavita.example", apiKey: "key")
        )
        return KavitaClient(address: address, configuration: KavitaStub.configuration())
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

    /// A box, because the stub runs on the session's queue.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }
}

/// A transport that answers from a closure.
final class KavitaStub: URLProtocol {
    enum Answer {
        case response(status: Int, body: Data)
    }

    nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Answer)?
    nonisolated(unsafe) static var seen: [String] = []

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KavitaStub.self]
        return configuration
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let answer = Self.answer?(request),
              case let .response(status, body) = answer,
              let url = request.url,
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
