import Foundation
import Testing

@testable import Kavita

/// Reading a Kavita server's structure, against the mock this repository ships.
///
/// The fixtures are the mock's own responses, copied. That is the point: when someone
/// points StoryArc at a real Kavita and finds a difference, correcting the mock and
/// correcting these together is what stops the difference from being lost.
struct KavitaLibraryTests {
    /// A client on a host nothing else is using, so these tests can run beside others.
    private func client(_ body: String) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            request.url?.path().contains("authenticate") == true
                ? .response(status: 200, body: Data(#"{"username":"a","token":"t"}"#.utf8))
                : .response(status: 200, body: Data(body.utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "k"))
        return KavitaClient(address: address, configuration: configuration)
    }

    @Test("Libraries come back with their names")
    func libraries() async throws {
        let client = try client(#"[{"id":1,"name":"Comics","type":0},{"id":2,"name":"Books"}]"#)
        let libraries = try await client.libraries()
        #expect(libraries.map(\.name) == ["Comics", "Books"])
    }

    @Test("A series reports how far through it the server thinks you are")
    func seriesProgress() async throws {
        let client = try client(
            #"[{"id":1,"name":"Tidal Reach","libraryId":1,"pages":24,"pagesRead":6}]"#
        )
        let series = try await client.series(inLibrary: 1)
        #expect(series.first?.fraction == 0.25)
    }

    @Test("A series the server has not scanned has no progress rather than none read")
    func unscannedSeries() async throws {
        // A bar at zero would say "unread" about something the server does not yet know.
        let client = try client(#"[{"id":1,"name":"New","libraryId":1,"pages":0,"pagesRead":0}]"#)
        #expect(try await client.series().first?.fraction == nil)
    }

    @Test("Loose chapters are distinguished from a volume")
    func looseChapters() async throws {
        // Kavita models chapters belonging to no volume as volume zero. Without the
        // distinction every such series shows a phantom "Volume 0".
        let client = try client("""
        [{"id":10,"number":0,"chapters":[{"id":1,"number":"1","pages":8,"pagesRead":8}]},
         {"id":11,"number":1,"name":"Volume 1","chapters":[]}]
        """)
        let volumes = try await client.volumes(ofSeries: 1)
        #expect(volumes.first?.isLooseChapters == true)
        #expect(volumes.last?.isLooseChapters == false)
    }

    @Test("A chapter with no title is named by its number")
    func chapterNaming() {
        // Kavita leaves the title empty for a plain numbered issue, and "3" beats a blank
        // row.
        #expect(KavitaChapter(id: 1, number: "3").displayName == "3")
        #expect(KavitaChapter(id: 1, number: "3", title: "").displayName == "3")
        #expect(KavitaChapter(id: 1, number: "3", title: "The Gathering").displayName
            == "The Gathering")
    }

    @Test("A chapter is finished when every page is read")
    func chapterFinished() {
        #expect(KavitaChapter(id: 1, number: "1", pages: 8, pagesRead: 8).isFinished)
        #expect(!KavitaChapter(id: 1, number: "1", pages: 8, pagesRead: 7).isFinished)
        // Not finished, because nothing is known — the same reason a series with no pages
        // reports no progress.
        #expect(!KavitaChapter(id: 1, number: "1", pages: 0, pagesRead: 0).isFinished)
    }

    @Test("A search reads all five kinds the spec names")
    func findsEveryKind() async throws {
        // `kavita-server`: "matches across series, chapters, people, genres, and tags". A
        // genre and a tag arrive as one kind, and in that order.
        let client = try client(everyKind)
        let hits = try await client.find("a")
        #expect(hits.map(\.kind) == [.series, .chapter, .person, .subject, .subject])
        #expect(
            hits.map(\.title) == ["Tidal Reach", "The Harbour", "Ada Okonkwo", "Adventure", "Ongoing"]
        )
    }

    @Test("A chapter found by name carries the series it opens")
    func foundChapterOpens() async throws {
        // Kavita's search DTO spells a chapter's title `titleName`. Read from the wrong
        // field, a chapter found by name is listed as a bare number and opens nothing.
        let client = try client(everyKind)
        let chapter = try #require(try await client.find("harbour").first { $0.kind == .chapter })
        #expect(chapter.title == "The Harbour")
        #expect(chapter.isOpenable)
        #expect(chapter.seriesId == 2)
    }

    @Test("A person is a name rather than a place")
    func foundPersonOpensNothing() async throws {
        // Kavita answers a person with a name alone, so the row is plainly not tappable
        // rather than tappable and inert.
        let client = try client(everyKind)
        let person = try #require(try await client.find("okonkwo").first { $0.kind == .person })
        #expect(!person.isOpenable)
    }

    /// One answer carrying all five kinds, which the Android suite stubs identically.
    private let everyKind = """
    {"series":[{"id":2,"name":"Tidal Reach"}],
     "chapters":[{"id":9,"titleName":"The Harbour","seriesId":2}],
     "persons":[{"id":1,"name":"Ada Okonkwo"}],
     "genres":[{"id":1,"title":"Adventure"}],
     "tags":[{"id":2,"title":"Ongoing"}]}
    """

    @Test("The series list is asked for with a post, which is the only verb Kavita answers")
    func seriesListIsPosted() async throws {
        // Measured against a live Kavita on 2026-09-06: `GET /api/Series/all-v2` answers 404
        // and a POST carrying an empty filter answers with every series. A reader who added
        // their own server was shown no series at all, and no test could see it because the
        // mock answered any verb. `scripts/kavita-server.mjs --self-test` holds the server's
        // half of this claim, and Android's `KavitaTest` the same client half.
        let sent = KavitaSent()
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"a","token":"t"}"#.utf8))
            }
            sent.record(request)
            return .response(status: 200, body: Data("[]".utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "k"))
        let client = KavitaClient(address: address, configuration: configuration)
        _ = try await client.series(inLibrary: 1)

        let request = try #require(sent.request)
        #expect(request.url?.path() == "/api/Series/all-v2")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("The library a reader picked rides in the filter, and never in the query")
    func libraryRidesInTheFilter() async throws {
        // Measured against a live Kavita on 2026-09-06: `POST /api/Series/all-v2?libraryId=3`
        // answered all 215 series across four libraries, so the parameter this client used to
        // send did nothing at all. The same route carrying this statement answered 91 series
        // from library 3 alone. Field 19 is `Libraries` in Kavita's `SeriesFilterField`.
        // A reader who picked one library was shown every library, and the request succeeded,
        // so nothing anywhere reported a problem.
        let sent = KavitaSent()
        let client = try recording(sent, answering: .response(status: 200, body: Data("[]".utf8)))
        _ = try await client.series(inLibrary: 3)

        let request = try #require(sent.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.query() == nil)

        let filter = try JSONDecoder().decode(SentFilter.self, from: try #require(sent.body))
        #expect(filter.combination == 0)
        #expect(filter.statements.count == 1)
        #expect(filter.statements.first?.field == 19)
        #expect(filter.statements.first?.comparison == 0)
        #expect(filter.statements.first?.value == "3")
    }

    @Test("A listing of the whole server carries no statement at all")
    func everyLibraryCarriesNoStatement() async throws {
        // An empty filter is what a live Kavita answers with everything, and it is what this
        // client has always sent. A statement naming no library would be a filter this
        // repository has not measured.
        let sent = KavitaSent()
        let client = try recording(sent, answering: .response(status: 200, body: Data("[]".utf8)))
        _ = try await client.series()
        #expect(String(bytes: try #require(sent.body), encoding: .utf8) == "{}")
    }

    @Test("A server that does not know the series list is asked once and then refused")
    func aMissingRouteIsRememberedOnce() async throws {
        // A client cannot ask a Kavita what version it is: every version route answered 404
        // or 403 on 2026-09-06, and swagger is off in production. So a 404 on the route
        // itself is the only signal, and paying for it on every listing is the cost this
        // remembers away.
        let calls = Calls()
        let client = try counting(calls, answering: .response(status: 404, body: Data()))

        let missing = KavitaError.routeMissing(path: "Series/all-v2")
        await #expect(throws: missing) { _ = try await client.series() }
        await #expect(throws: missing) { _ = try await client.series() }
        #expect(calls.count == 1)
    }

    @Test("A refused key is not remembered as a server that is too old")
    func aRefusedKeyIsNotAnOldServer() async throws {
        // A 401, a 403, a 500 or a timeout is the key or the server being wrong for a moment.
        // Reading one of them as "old server" would turn one expired token into a permanent
        // downgrade for that server, which no later good answer could undo.
        let refuse = Calls()
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"a","token":"t"}"#.utf8))
            }
            return refuse.isOn
                ? .response(status: 401, body: Data())
                : .response(status: 200, body: Data(#"[{"id":1,"name":"Tidal Reach"}]"#.utf8))
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "k"))
        let client = KavitaClient(address: address, configuration: configuration)

        refuse.isOn = true
        await #expect(throws: KavitaError.keyRejected) { _ = try await client.series() }
        refuse.isOn = false
        #expect(try await client.series().count == 1)
    }

    /// A client whose every non-authenticating request is recorded and answered the same way.
    private func recording(
        _ sent: KavitaSent,
        answering answer: KavitaStub.Answer
    ) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"a","token":"t"}"#.utf8))
            }
            sent.record(request)
            return answer
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "k"))
        return KavitaClient(address: address, configuration: configuration)
    }

    /// The same, counting the requests to the series list rather than keeping the last one.
    private func counting(
        _ calls: Calls,
        answering answer: KavitaStub.Answer
    ) throws -> KavitaClient {
        let host = "\(UUID().uuidString).example"
        let configuration = KavitaStub.session(host: host) { request in
            if request.url?.path().contains("authenticate") == true {
                return .response(status: 200, body: Data(#"{"username":"a","token":"t"}"#.utf8))
            }
            calls.bump()
            return answer
        }
        let address = try #require(KavitaAddress.from(base: "https://\(host)", apiKey: "k"))
        return KavitaClient(address: address, configuration: configuration)
    }

    /// What the client posted, read back as Kavita's own `SeriesFilterV2Dto`.
    private struct SentFilter: Decodable {
        let statements: [SentStatement]
        let combination: Int
    }

    /// One clause of that filter.
    private struct SentStatement: Decodable {
        let comparison: Int
        let field: Int
        let value: String
    }

    /// A box, because the stub runs on the session's queue.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = 0
        private var refusing = false

        func bump() { lock.withLock { seen += 1 } }

        var count: Int { lock.withLock { seen } }

        var isOn: Bool {
            get { lock.withLock { refusing } }
            set { lock.withLock { refusing = newValue } }
        }
    }

    @Test("A response that is not the shape expected is named as such")
    func unexpectedShape() async throws {
        let client = try client(#"{"unexpected":true}"#)
        await #expect(throws: KavitaError.unexpectedResponse) {
            _ = try await client.libraries()
        }
    }
}
