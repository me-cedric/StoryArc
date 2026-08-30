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

    @Test("A search returns the series the server matched")
    func search() async throws {
        let client = try client(
            #"{"series":[{"id":2,"name":"Tidal Reach","libraryId":1}],"chapters":[]}"#
        )
        #expect(try await client.search("tidal").map(\.name) == ["Tidal Reach"])
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

    @Test("A response that is not the shape expected is named as such")
    func unexpectedShape() async throws {
        let client = try client(#"{"unexpected":true}"#)
        await #expect(throws: KavitaError.unexpectedResponse) {
            _ = try await client.libraries()
        }
    }
}
