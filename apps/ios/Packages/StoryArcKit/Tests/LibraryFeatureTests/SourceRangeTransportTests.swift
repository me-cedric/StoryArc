import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A streamed read carries the reading source's own credential, to the reading source's own
/// origin, over a connection that trusts the reading source's own pins — and nowhere else.
///
/// dl-core 1.6: `HttpSource`'s default transport is unauthenticated and unpinned, so a
/// catalogue behind Basic, Bearer or a pinned self-signed certificate answered 401 or failed
/// TLS the moment a reader opened a book while it was still arriving.
@Suite("The streamed-read transport", .serialized)
@MainActor
struct SourceRangeTransportTests {

    /// Answers every request the same way, and remembers the last one it saw.
    ///
    /// Registered process-wide, like `OpdsClientTests`' own stub, which is why this suite is
    /// `.serialized`.
    private final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var authorization: String?
        nonisolated(unsafe) static var url: URL?

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.authorization = request.value(forHTTPHeaderField: "Authorization")
            Self.url = request.url
            guard let from = request.url,
                  let response = HTTPURLResponse(
                      url: from,
                      statusCode: 206,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Range": "bytes 0-0/10"]
                  )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data([0]))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return configuration
    }

    private func transport(sources: [Source], credentials: CredentialStore?) -> SourceRangeTransport {
        SourceRangeTransport(
            pins: CertificatePins(),
            credentials: credentials,
            sources: { sources },
            configuration: configuration
        )
    }

    @Test("A source configured at the address sends its credential")
    func credentialTravelsToItsOwnSource() async throws {
        let credentials = CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
        let sourceID = UUID()
        let reference = CredentialStore.reference(for: sourceID)
        #expect(credentials.save(OpdsCredential.bearer(token: "abc123").stored, for: reference))
        defer { credentials.remove(reference) }

        let source = Source(
            id: sourceID,
            displayName: "Library",
            kind: .opdsCatalog,
            credentialReference: reference,
            locator: "https://library.example"
        )
        let transport = transport(sources: [source], credentials: credentials)

        let url = try #require(URL(string: "https://library.example/book.epub"))
        _ = try await transport.fetch(url, from: 0, through: 0)

        #expect(Stub.authorization == "Bearer abc123")
    }

    @Test("An address with no configured source carries no credential")
    func noMatchingSourceSendsNoCredential() async throws {
        // `startLoading()` overwrites `Stub.authorization` with this request's own header,
        // present or not, so a value another test left behind proves nothing either way.
        let transport = transport(sources: [], credentials: nil)
        let url = try #require(URL(string: "https://elsewhere.invalid/book.epub"))
        _ = try await transport.fetch(url, from: 0, through: 0)

        #expect(Stub.authorization == nil)
    }

    @Test("A source's credential does not follow a different address")
    func credentialDoesNotFollowAnotherOrigin() async throws {
        let credentials = CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
        let sourceID = UUID()
        let reference = CredentialStore.reference(for: sourceID)
        #expect(credentials.save(OpdsCredential.bearer(token: "abc123").stored, for: reference))
        defer { credentials.remove(reference) }

        let source = Source(
            id: sourceID,
            displayName: "Library",
            kind: .opdsCatalog,
            credentialReference: reference,
            locator: "https://library.example"
        )
        let transport = transport(sources: [source], credentials: credentials)

        let url = try #require(URL(string: "https://elsewhere.invalid/book.epub"))
        _ = try await transport.fetch(url, from: 0, through: 0)

        #expect(Stub.authorization == nil)
    }

    @Test("A non-web address is refused before any request is made")
    func nonWebAddressIsRefused() async throws {
        let transport = transport(sources: [], credentials: nil)
        let url = try #require(URL(string: "file:///etc/passwd"))
        await #expect(throws: SourceRangeTransportError.unfetchable) {
            _ = try await transport.fetch(url, from: 0, through: 0)
        }
    }
}
