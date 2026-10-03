import Catalogue
import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// A catalogue's continuation: ``OpdsContributor/page(source:page:url:client:)`` asked a
/// second time, for the link the first page named rather than the catalogue's own root.
///
/// A stubbed transport, like `OpdsCoverTests`' own: `client` is the seam, and the one thing
/// under test is which URL a second request reaches.
///
/// `.serialized`: `Stub.answer` is one static closure shared by every test's client, the
/// same constraint `OpdsClientTests`' and `OpdsCoverTests`' own stubs have.
@Suite(.serialized)
struct OpdsContinuedReadTests {

    private func feed(entry: String, next: String?) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Library</title>
          \(next.map { "<link rel=\"next\" href=\"\($0)\" type=\"application/atom+xml\"/>" } ?? "")
          <entry>
            <title>\(entry)</title>
            <id>urn:uuid:\(entry)</id>
            <link rel="http://opds-spec.org/acquisition" href="download.cbz"
                  type="application/vnd.comicbook+zip"/>
          </entry>
        </feed>
        """
    }

    @Test("A continuation asks for the next link, not the catalogue's root again")
    func continuationFollowsTheNextLink() async throws {
        Stub.answer = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("page2") {
                return .response(status: 200, headers: [:], body: Data(self.feed(entry: "Second Wave", next: nil).utf8))
            }
            return .response(status: 200, headers: [:], body: Data(self.feed(entry: "Tidal Reach", next: "page2").utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let sourceID = UUID()
        let catalogue = Source(
            id: sourceID, displayName: "Library", kind: .opdsCatalog,
            locator: "https://library.example/opds/page1"
        )
        let page = try #require(CataloguePage(source: catalogue, credentials: nil))
        let client = OpdsClient(origin: page.origin, configuration: configuration)

        let first = try await OpdsContributor.page(source: sourceID, page: page, url: page.url, client: client)
        #expect(first.slice.publications.map(\.displayTitle) == ["Tidal Reach"])
        #expect(first.slice.holdsMore)
        let nextURL = try #require(first.next)
        #expect(nextURL.absoluteString == "https://library.example/opds/page2")

        // The bug this fixes: a continuation that always re-read `page.url` would land back
        // on page one here instead. Mutate the call below to `url: page.url` and this fails,
        // because the second page would then answer "Tidal Reach" again, not "Second Wave".
        let second = try await OpdsContributor.page(source: sourceID, page: page, url: nextURL, client: client)
        #expect(second.slice.publications.map(\.displayTitle) == ["Second Wave"])
        #expect(!second.slice.holdsMore)
        #expect(second.next == nil)
    }
}

/// A transport that answers from a closure. `OpdsCoverTests`' and `OpdsClientTests`' own
/// stub carries the same shape, each scoped to its own suite.
private final class Stub: URLProtocol, @unchecked Sendable {
    enum Answer {
        case response(status: Int, headers: [String: String], body: Data)
    }

    nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Answer)?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let answered = Self.answer?(request),
              case let .response(status, headers, body) = answered,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
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
