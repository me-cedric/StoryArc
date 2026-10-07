import Foundation
import Testing

@testable import Catalogue
@testable import StoryArcCore

/// A transport that answers from a closure, for this suite alone.
///
/// Not `StubProtocol`. `.serialized` orders the tests *within* a suite and nothing between
/// two suites, so sharing that class's one static closure made this suite and
/// `OpdsClientTests` answer each other's requests — four of its cases failed the first time
/// these tests ran beside it. A class of its own is the cheapest way to keep them apart,
/// because the addresses here are the providers' own and cannot be made unique per test.
final class CoverStub: URLProtocol {
    enum Answer {
        case response(status: Int, headers: [String: String], body: Data)
    }

    nonisolated(unsafe) static var answer: (@Sendable (URLRequest) -> Answer)?

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let answered = Self.answer?(request),
              case let .response(status, headers, body) = answered,
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

/// The lookup, against a stubbed transport.
///
/// Serialised because ``CoverStub`` holds one closure for the whole suite, the way a
/// `URLProtocol` has to.
@Suite(.serialized)
struct CoverLookupClientTests {
    /// Every request the stub saw, which is what the egress assertions read.
    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func append(_ url: URL?) {
            guard let url else { return }
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var value: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    private func client(
        enabled: Bool,
        cache: CoverLookupCache,
        _ stub: @escaping @Sendable (URLRequest) -> CoverStub.Answer
    ) -> CoverLookupClient {
        CoverStub.answer = stub
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverStub.self]
        return CoverLookupClient(
            isEnabled: { enabled }, cache: cache, configuration: configuration
        )
    }

    private func cache() -> CoverLookupCache {
        CoverLookupCache(
            file: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(UUID().uuidString).json")
        )
    }

    @Test("Nothing is asked while the setting is off")
    func asksNothingWhileTheSettingIsOff() async {
        // `cover-art`: "a reader has never opened the cover-lookup setting ... no cover
        // request is made to any third party". Task 3.5 asks for exactly this assertion.
        let asked = Asked()
        let client = client(enabled: false, cache: cache()) { request in
            asked.append(request.url)
            return .response(status: 200, headers: [:], body: Data([0xFF]))
        }

        let found = await client.cover(for: "pub", identifier: .isbn("9780141187761"))

        #expect(found == nil)
        #expect(asked.value.isEmpty)
    }

    @Test("A title search is silent too while the setting is off")
    func searchesNothingWhileTheSettingIsOff() async {
        let asked = Asked()
        let client = client(enabled: false, cache: cache()) { request in
            asked.append(request.url)
            return .response(status: 200, headers: [:], body: Data("{}".utf8))
        }

        let candidates = await client.candidates(title: "Fine Print")

        #expect(candidates.isEmpty)
        #expect(asked.value.isEmpty)
    }

    @Test("A provider that answers with a picture gives back its address")
    func readsAPictureAnswer() async throws {
        let client = client(enabled: true, cache: cache()) { _ in
            .response(status: 200, headers: ["Content-Type": "image/jpeg"], body: Data([0xFF, 0xD8]))
        }

        let found = await client.cover(for: "pub", identifier: .isbn("9780141187761"))

        #expect(found?.host() == "covers.openlibrary.org")
    }

    @Test("Audnexus answers with a document, and the image field is read out of it")
    func readsADocumentAnswer() async throws {
        let body = #"{"asin":"B08G9PRS1K","image":"https://m.media-amazon.com/images/I/c.jpg"}"#
        let client = client(enabled: true, cache: cache()) { _ in
            .response(status: 200, headers: [:], body: Data(body.utf8))
        }

        let found = await client.cover(for: "pub", identifier: .audibleASIN("B08G9PRS1K"))

        #expect(found?.absoluteString == "https://m.media-amazon.com/images/I/c.jpg")
    }

    @Test("An answer naming a host the setting does not name is not followed")
    func refusesAnUnlistedHost() async {
        // A provider's answer can name any address at all. Fetched, it would send a request
        // to a host the reader never agreed to, which non-negotiable 2 forbids.
        for image in ["https://tracker.example/c.jpg", "http://m.media-amazon.com/c.jpg"] {
            let body = #"{"asin":"B08G9PRS1K","image":"\#(image)"}"#
            let client = client(enabled: true, cache: cache()) { _ in
                .response(status: 200, headers: [:], body: Data(body.utf8))
            }

            let found = await client.cover(for: "pub", identifier: .audibleASIN("B08G9PRS1K"))

            #expect(found == nil, "Followed \(image)")
        }
    }

    @Test("One picture is one candidate, a picture off the listed hosts is none, and a title is asked once")
    func titleSearchIsDedupedFilteredAndCached() async {
        let body = #"""
        {"data":{"Page":{"media":[
          {"title":{"romaji":"A"},"coverImage":{"large":"https://s4.anilist.co/1.jpg"}},
          {"title":{"romaji":"B"},"coverImage":{"large":"https://s4.anilist.co/1.jpg"}},
          {"title":{"romaji":"C"},"coverImage":{"large":"https://tracker.example/2.jpg"}}]}}}
        """#
        let asked = Asked()
        let client = client(enabled: true, cache: cache()) { request in
            asked.append(request.url)
            return .response(status: 200, headers: [:], body: Data(body.utf8))
        }

        let first = await client.candidates(title: "Kaze", from: [.aniList])
        let second = await client.candidates(title: "Kaze", from: [.aniList])

        #expect(first.map(\.imageURL.absoluteString) == ["https://s4.anilist.co/1.jpg"])
        #expect(second == first)
        #expect(asked.value.count == 1)
    }

    @Test("A plus sign in a title is searched as a plus sign")
    func plusIsEscaped() throws {
        // `URLQueryItem` leaves `+` bare, and a server reads a bare `+` as a space.
        let web = try #require(CoverWebSearch.url(title: "C++ Primer"))
        #expect(web.absoluteString.contains("C%2B%2B"))
        let search = try #require(CoverTitleSearch.request(.openLibrary, title: "C++ Primer")?.url)
        #expect(search.absoluteString.contains("C%2B%2B"))
    }

    @Test("One publication is asked about once, whatever the answer was")
    func asksOncePerPublication() async {
        // `cover-art`: "the same publication is never looked up twice, because a provider
        // that asks not to be crawled is entitled to that".
        let asked = Asked()
        let shared = cache()
        let client = client(enabled: true, cache: shared) { request in
            asked.append(request.url)
            return .response(status: 404, headers: [:], body: Data())
        }

        _ = await client.cover(for: "pub", identifier: .isbn("9780141187761"))
        _ = await client.cover(for: "pub", identifier: .isbn("9780141187761"))

        #expect(asked.value.count == 1)
    }

    @Test("A picture is fetched once and kept, whichever size asks for it next")
    func keepsThePicture() async {
        let asked = Asked()
        let shared = cache()
        let first = client(enabled: true, cache: shared) { request in
            asked.append(request.url)
            return .response(status: 200, headers: [:], body: Data("jpeg".utf8))
        }
        let identifier = CoverIdentifier.isbn("9780141187761")

        let one = await first.coverImage(for: "pub", identifier: identifier)
        let two = await first.coverImage(for: "pub", identifier: identifier)

        #expect(one == Data("jpeg".utf8))
        #expect(two == one)
        #expect(asked.value.count == 1)
    }

    @Test("A kept picture survives the cache being made again, and is not asked for again")
    func keptPictureSurvivesRelaunch() async {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).json")
        let identifier = CoverIdentifier.isbn("9780141187761")
        _ = await client(enabled: true, cache: CoverLookupCache(file: file)) { _ in
            .response(status: 200, headers: [:], body: Data("jpeg".utf8))
        }.coverImage(for: "pub", identifier: identifier)
        let asked = Asked()

        let later = await client(enabled: true, cache: CoverLookupCache(file: file)) { request in
            asked.append(request.url)
            return .response(status: 500, headers: [:], body: Data())
        }.coverImage(for: "pub", identifier: identifier)

        #expect(later == Data("jpeg".utf8))
        #expect(asked.value.isEmpty)
    }

    @Test("A document answer costs two requests the first time and none after")
    func documentAnswerIsKept() async {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).json")
        let asked = Asked()
        let answer: @Sendable (URLRequest) -> CoverStub.Answer = { request in
            asked.append(request.url)
            let body = request.url?.host() == "api.audnex.us"
                ? #"{"image":"https://m.media-amazon.com/images/I/c.jpg"}"# : "jpeg"
            return .response(status: 200, headers: [:], body: Data(body.utf8))
        }
        let asin = CoverIdentifier.audibleASIN("B08G9PRS1K")

        _ = await client(enabled: true, cache: CoverLookupCache(file: file), answer)
            .coverImage(for: "pub", identifier: asin)
        let again = await client(enabled: true, cache: CoverLookupCache(file: file), answer)
            .coverImage(for: "pub", identifier: asin)

        #expect(again == Data("jpeg".utf8))
        #expect(asked.value.compactMap { $0.host() } == ["api.audnex.us", "m.media-amazon.com"])
    }

    @Test("A document answer whose picture is refused is not asked for again")
    func refusedPictureIsRecorded() async {
        let asked = Asked()
        let shared = cache()
        let refused = client(enabled: true, cache: shared) { request in
            asked.append(request.url)
            guard request.url?.host() == "api.audnex.us" else {
                return .response(status: 404, headers: [:], body: Data())
            }
            let document = #"{"image":"https://m.media-amazon.com/images/I/c.jpg"}"#
            return .response(status: 200, headers: [:], body: Data(document.utf8))
        }
        let asin = CoverIdentifier.audibleASIN("B08G9PRS1K")

        let first = await refused.coverImage(for: "pub", identifier: asin)
        let again = await refused.coverImage(for: "pub", identifier: asin)

        #expect(first == nil)
        #expect(again == nil)
        #expect(asked.value.compactMap { $0.host() } == ["api.audnex.us", "m.media-amazon.com"])
    }

    @Test("A kept picture is not handed out while the setting is off")
    func keptPictureIsGatedToo() async {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).json")
        let identifier = CoverIdentifier.isbn("9780141187761")
        _ = await client(enabled: true, cache: CoverLookupCache(file: file)) { _ in
            .response(status: 200, headers: [:], body: Data("jpeg".utf8))
        }.coverImage(for: "pub", identifier: identifier)

        let off = await client(enabled: false, cache: CoverLookupCache(file: file)) { _ in
            .response(status: 200, headers: [:], body: Data("jpeg".utf8))
        }.coverImage(for: "pub", identifier: identifier)

        #expect(off == nil)
    }

    @Test("An empty answer is no picture and is not asked for twice")
    func emptyAnswerIsARefusal() async {
        let asked = Asked()
        let shared = cache()
        let identifier = CoverIdentifier.isbn("9780141187761")
        let empty = client(enabled: true, cache: shared) { request in
            asked.append(request.url)
            return .response(status: 200, headers: [:], body: Data())
        }

        let first = await empty.coverImage(for: "pub", identifier: identifier)
        _ = await empty.coverImage(for: "pub", identifier: identifier)

        #expect(first == nil)
        #expect(asked.value.count == 1)
    }

    @Test("A refusal is quiet: no throw, no error, the cover unchanged")
    func refusalsAreQuiet() async {
        // 403, 404, 429 or silence all come back the same way, because they are the same
        // outcome for the reader: the publication keeps the cover it had.
        for status in [403, 404, 429, 500] {
            let client = client(enabled: true, cache: cache()) { _ in
                .response(status: status, headers: [:], body: Data())
            }
            let found = await client.cover(for: "pub", identifier: .isbn("9780141187761"))
            #expect(found == nil, "status \(status) should answer nil rather than throw")
        }
    }

    @Test("A publication can be asked again once its answer is forgotten")
    func forgettingAllowsOneMoreAsk() async {
        // The escape hatch a cached 429 needs: the provider was asking for later, and a
        // reader asking by hand is the later. Nothing else re-asks.
        let asked = Asked()
        let shared = cache()
        let client = client(enabled: true, cache: shared) { request in
            asked.append(request.url)
            return .response(status: 429, headers: [:], body: Data())
        }

        _ = await client.cover(for: "pub", identifier: .isbn("9780141187761"))
        await shared.forget("pub")
        _ = await client.cover(for: "pub", identifier: .isbn("9780141187761"))

        #expect(asked.value.count == 2)
    }

    @Test("An answer survives the cache being made again from the same file")
    func writesTheAnswerToDisk() async throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).json")
        let first = CoverLookupCache(file: file)
        let answer = CoverLookupAnswer(
            provider: .openLibrary, imageURL: URL(string: "https://covers.example/1.jpg")
        )

        await first.record(answer, for: "pub")
        let second = CoverLookupCache(file: file)

        #expect(await second.answer(for: "pub") == answer)
    }

    @Test("A refusal is recorded as well as a hit")
    func recordsARefusal() async {
        let shared = cache()
        let client = client(enabled: true, cache: shared) { _ in
            .response(status: 404, headers: [:], body: Data())
        }

        _ = await client.cover(for: "pub", identifier: .isbn("9780141187761"))

        let recorded = await shared.answer(for: "pub")
        #expect(recorded?.imageURL == nil)
        #expect(recorded?.provider == .openLibrary)
    }
}
