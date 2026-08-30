import Foundation
import Testing

@testable import Catalogue

/// The client, against a stubbed transport.
///
/// A `URLProtocol` stub rather than a live server: the behaviour under test is what the
/// app does with a 401, a 404 and a redirect, and none of those need a socket.
///
/// Serialised, because the stub is registered process-wide. Run in parallel, the tests set
/// each other's answers and every one of them saw the 401.
@Suite(.serialized)
struct OpdsClientTests {
    private static let atom = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Stubbed Library</title>
      <link rel="subsection" href="unread" title="Unread"
            type="application/atom+xml;profile=opds-catalog"/>
    </feed>
    """

    private func client(
        origin: OpdsOrigin? = nil,
        _ stub: @escaping @Sendable (URLRequest) -> StubProtocol.Answer
    ) -> OpdsClient {
        StubProtocol.answer = stub
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return OpdsClient(origin: origin, configuration: configuration)
    }

    @Test func aFeedIsFetchedAndParsed() async throws {
        let client = client { _ in
            .response(status: 200, headers: ["Content-Type": "application/atom+xml"], body: Data(Self.atom.utf8))
        }
        let feed = try await client.feed(at: URL(string: "https://library.example/opds/")!)
        #expect(feed.title == "Stubbed Library")
        #expect(feed.navigation.first?.href.absoluteString == "https://library.example/opds/unread")
    }

    @Test func aCredentialBecomesAnAuthorizationHeader() async throws {
        let seen = Captured()
        let client = client { request in
            seen.value = request.value(forHTTPHeaderField: "Authorization")
            return .response(status: 200, headers: [:], body: Data(Self.atom.utf8))
        }
        _ = try await client.feed(
            at: URL(string: "https://library.example/opds/")!,
            credential: .basic(user: "ada", password: "lovelace")
        )
        // base64("ada:lovelace")
        #expect(seen.value == "Basic YWRhOmxvdmVsYWNl")
    }

    @Test func aBearerTokenIsSentAsOne() async throws {
        let seen = Captured()
        let client = client { request in
            seen.value = request.value(forHTTPHeaderField: "Authorization")
            return .response(status: 200, headers: [:], body: Data(Self.atom.utf8))
        }
        _ = try await client.feed(
            at: URL(string: "https://library.example/opds/")!,
            credential: .bearer(token: "abc123")
        )
        #expect(seen.value == "Bearer abc123")
    }

    @Test func aChallengeSaysWhichSchemeToAskFor() async throws {
        let client = client { _ in
            .response(status: 401, headers: ["WWW-Authenticate": "Basic realm=\"opds\""], body: Data())
        }
        await #expect(throws: OpdsError.unauthorized(scheme: .basic)) {
            try await client.feed(at: URL(string: "https://library.example/opds/")!)
        }
    }

    @Test func aChallengeWithNoSchemeStillSaysUnauthorized() async throws {
        let client = client { _ in .response(status: 401, headers: [:], body: Data()) }
        await #expect(throws: OpdsError.unauthorized(scheme: nil)) {
            try await client.feed(at: URL(string: "https://library.example/opds/")!)
        }
    }

    @Test func anHttpFailureCarriesItsStatus() async throws {
        let client = client { _ in .response(status: 404, headers: [:], body: Data()) }
        await #expect(throws: OpdsError.http(status: 404)) {
            try await client.feed(at: URL(string: "https://library.example/opds/nope")!)
        }
    }

    @Test func anHtmlBodyIsNamedRatherThanParsedAsAFeed() async throws {
        let client = client { _ in
            .response(
                status: 200,
                headers: ["Content-Type": "text/html"],
                body: Data("<!DOCTYPE html><html><body>Sign in</body></html>".utf8)
            )
        }
        await #expect(throws: OpdsError.notAFeed(received: .html)) {
            try await client.feed(at: URL(string: "https://library.example/opds/")!)
        }
    }

    @Test func relativeLinksResolveAgainstWhereTheResponseCameFrom() async throws {
        // A redirect moves what a relative href is relative to. Resolving against the
        // request would point every link on the page at the old host.
        let client = client { _ in
            .response(
                status: 200,
                headers: [:],
                body: Data(Self.atom.utf8),
                url: URL(string: "https://moved.example/catalogue/")!
            )
        }
        let feed = try await client.feed(at: URL(string: "https://library.example/opds/")!)
        #expect(feed.navigation.first?.href.absoluteString == "https://moved.example/catalogue/unread")
    }

    @Test func aFileIsFetchedAsBytes() async throws {
        let client = client { _ in .response(status: 200, headers: [:], body: Data([1, 2, 3])) }
        let data = try await client.data(at: URL(string: "https://library.example/1.epub")!)
        #expect(data == Data([1, 2, 3]))
    }

    // MARK: - Where the credential is allowed to go

    @Test func aCredentialDoesNotFollowTheFeedToAnotherHost() async throws {
        // The rank-2 case. A compromised catalogue puts an absolute href on its own host
        // into the feed; without an origin the closure hands it the reader's password.
        let seen = Captured()
        let home = try #require(URL(string: "https://books.example/opds/"))
        let books = try #require(OpdsOrigin(url: home))
        let client = client(origin: books) { request in
            seen.value = request.value(forHTTPHeaderField: "Authorization")
            return .response(status: 200, headers: [:], body: Data([1, 2, 3]))
        }
        _ = try await client.data(
            at: try #require(URL(string: "https://collect.attacker.example/x.jpg")),
            credential: .basic(user: "ada", password: "lovelace")
        )
        #expect(seen.value == nil)
    }

    @Test func aCredentialStillTravelsToTheSourceItBelongsTo() async throws {
        let seen = Captured()
        let home = try #require(URL(string: "https://books.example/opds/"))
        let books = try #require(OpdsOrigin(url: home))
        let client = client(origin: books) { request in
            seen.value = request.value(forHTTPHeaderField: "Authorization")
            return .response(status: 200, headers: [:], body: Data(Self.atom.utf8))
        }
        _ = try await client.feed(
            at: try #require(URL(string: "https://books.example/opds/page/2")),
            credential: .basic(user: "ada", password: "lovelace")
        )
        #expect(seen.value == "Basic YWRhOmxvdmVsYWNl")
    }

    @Test func aCredentialIsDroppedWhenARedirectChangesTheHost() async throws {
        let seen = Captured()
        let elsewhere = try #require(URL(string: "https://collect.attacker.example/opds/"))
        let home = try #require(URL(string: "https://books.example/opds/"))
        let books = try #require(OpdsOrigin(url: home))
        let client = client(origin: books) { request in
            guard request.url?.host() == "books.example" else {
                seen.value = request.value(forHTTPHeaderField: "Authorization")
                return .response(status: 200, headers: [:], body: Data(Self.atom.utf8))
            }
            return .redirect(to: elsewhere)
        }
        _ = try await client.feed(
            at: try #require(URL(string: "https://books.example/opds/")),
            credential: .basic(user: "ada", password: "lovelace")
        )
        #expect(seen.value == nil)
    }

    @Test func aFeedThatDowngradesToCleartextIsNotFollowed() async throws {
        // Rank 10: a misconfigured or hostile proxy answers `https` with `http` hrefs, and
        // Android's base config permits every one of them.
        let home = try #require(URL(string: "https://books.example/opds/"))
        let books = try #require(OpdsOrigin(url: home))
        let client = client(origin: books) { _ in
            .response(status: 200, headers: [:], body: Data(Self.atom.utf8))
        }
        await #expect(throws: OpdsError.refusedAddress) {
            try await client.feed(at: try #require(URL(string: "http://books.example/opds/")))
        }
    }

    @Test func anAddressThatIsNotHttpIsNotFetched() async throws {
        let client = client { _ in .response(status: 200, headers: [:], body: Data([1])) }
        await #expect(throws: OpdsError.refusedAddress) {
            try await client.data(at: try #require(URL(string: "file:///etc/hosts")))
        }
    }

    /// A box, because the stub runs on the session's queue and the test reads afterwards.
    private final class Captured: @unchecked Sendable {
        var value: String?
    }
}

/// A transport that answers from a closure.
final class StubProtocol: URLProtocol {
    enum Answer {
        case response(status: Int, headers: [String: String], body: Data, url: URL? = nil)

        /// A 302 the session is asked to follow, so the delegate's redirection hook runs.
        case redirect(to: URL)
    }

    /// Set by whichever test is running, which is why the suite above is serialised.
    /// `URLProtocol` registration is per-process and there is nowhere else to put this.
    nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Answer)?

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answered = Self.answer?(request)
        if case let .redirect(to) = answered {
            guard let from = request.url,
                  let response = HTTPURLResponse(
                      url: from,
                      statusCode: 302,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Location": to.absoluteString]
                  )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            // The headers come across, which is what `URLSession` itself does when it
            // follows a redirect and is the whole reason the hook has to exist.
            var next = request
            next.url = to
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        guard let answer = answered,
              case let .response(status, headers, body, url) = answer,
              let from = url ?? request.url,
              let response = HTTPURLResponse(
                  url: from,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
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

/// What the secure store holds, and what comes back out.
struct OpdsCredentialStorageTests {
    @Test func aPairSurvivesTheRoundTrip() throws {
        // A colon and a newline in the password. The colon is why the format is not
        // colon-separated; the newline is what a paste from a password manager can carry,
        // and it has to survive rather than truncate the password.
        let credential = OpdsCredential.basic(user: "ada", password: "love:lace\nx")
        #expect(OpdsCredential(stored: credential.stored) == credential)
    }

    @Test func aTokenSurvivesTheRoundTrip() throws {
        let credential = OpdsCredential.bearer(token: "abc123")
        #expect(OpdsCredential(stored: credential.stored) == credential)
    }

    @Test func aSchemeIsNotGuessed() {
        // Without the scheme, a reader who signed in with a token is sent back as Basic on
        // the next launch and the catalogue refuses them.
        #expect(OpdsCredential(stored: "ada\nlovelace") == nil)
        #expect(OpdsCredential(stored: "") == nil)
        #expect(OpdsCredential(stored: "digest\na\nb") == nil)
    }
}
