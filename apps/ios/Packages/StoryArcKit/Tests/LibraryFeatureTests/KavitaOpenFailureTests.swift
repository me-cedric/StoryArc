import Foundation
import Testing

import Kavita
@testable import LibraryFeature

/// A reading-list entry that does not open says why.
///
/// The field report: a comic opened from a Kavita reading list "showed a loader for ever". A
/// failed open cleared the row's spinner and said nothing else. These tests run
/// ``KavitaEntryOpening/attempt(_:from:)``, the call the list makes on a tap, against a stubbed
/// server, and read the reason the list then shows.
@Suite("Kavita reading-list open failures")
struct KavitaOpenFailureTests {

    /// One entry, in the shape `ReadingList/items` answers.
    private let entry = try? JSONDecoder().decode(
        KavitaReadingListItem.self,
        from: Data(#"""
        {"id": 1, "order": 0, "chapterId": 3103, "seriesId": 312, "seriesName": "Lantern Green",
         "pagesRead": 0, "pagesTotal": 22, "title": "Issue #43"}
        """#.utf8)
    )

    /// A client whose server answers the chapter download with `status` and `body`.
    private func client(host: String, status: Int, body: Data) throws -> KavitaClient {
        let address = KavitaAddress(base: try #require(URL(string: "http://\(host)")), apiKey: "key")
        return KavitaClient(address: address, configuration: EntryStub.session(host: host) { request in
            request.url?.path().hasSuffix("Plugin/authenticate") == true
                ? (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
                : (status, body)
        })
    }

    @Test("A download the server refuses is the server's failure")
    func refusedDownloadIsNotSent() async throws {
        let entry = try #require(entry)
        let opening = await KavitaEntryOpening.attempt(
            entry,
            from: try client(host: "refused.test", status: 500, body: Data())
        )
        #expect(opening.reason(server: "Attic") == KavitaEntryOpening.notSent.reason(server: "Attic"))
    }

    @Test("A file StoryArc cannot read is not blamed on the server")
    func unreadableFileIsUnreadable() async throws {
        let entry = try #require(entry)
        let opening = await KavitaEntryOpening.attempt(
            entry,
            from: try client(host: "garbled.test", status: 200, body: Data("not a comic".utf8))
        )
        #expect(opening.reason(server: "Attic") == KavitaEntryOpening.unreadable.reason(server: "Attic"))
    }

    @Test("Each reason names the server, and the two reasons differ")
    func reasonsNameTheServer() throws {
        let sent = try #require(KavitaEntryOpening.notSent.reason(server: "Attic"))
        let read = try #require(KavitaEntryOpening.unreadable.reason(server: "Attic"))
        #expect(sent.contains("Attic"))
        #expect(read.contains("Attic"))
        #expect(sent != read)
    }
}

/// A transport that answers from a closure, one per host, so parallel suites keep their own.
final class EntryStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: @Sendable (URLRequest) -> (Int, Data)] = [:]

    static func session(
        host: String,
        answer: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> URLSessionConfiguration {
        lock.withLock { answers[host] = answer }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EntryStub.self]
        return configuration
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let host = url.host(),
              let (status, body) = Self.lock.withLock({ Self.answers[host] })?(request),
              let response = HTTPURLResponse(
                  url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
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
