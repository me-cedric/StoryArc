import Foundation
import Kavita
@testable import LibraryFeature
import Testing

/// A series whose volumes call keeps failing is not lost -- it is retried.
///
/// Package `f4-read-core`, task 22.1's own corrected scope, item 4: "A series that fails its
/// volumes call two times is still lost until the next full read." A continuation page is
/// asked for once, so a series it could not read was gone for good until the whole
/// first-slice-and-continuation read started over. ``KavitaContributor/retry(source:client:seriesIDs:store:)``
/// is the second chance, fed by the ids ``KavitaContributor/page(source:client:page:store:)``
/// now reports in `failedSeriesIDs` instead of silently treating a failed series the same as
/// an empty one. Android's `KavitaContributorRetryTest` asks the same questions.
@Suite("A series the server keeps refusing is retried, not lost")
struct KavitaContributorRetryTests {

    /// A box, because the stub runs on the session's queue.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.withLock { defer { count += 1 }; return count } }
    }

    /// A client whose `Series/volumes` answers 500 the first `failures` times, then succeeds.
    private func client(failures: Int) throws -> KavitaClient {
        let host = "\(UUID().uuidString).contributor-retry.test"
        let calls = Counter()
        let configuration = EntryStub.session(host: host) { request in
            let path = request.url?.path() ?? ""
            if path.hasSuffix("Plugin/authenticate") {
                return (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
            }
            if path.hasSuffix("Series/recently-added-v2") {
                return (200, Data(#"[{"id": 312, "name": "Lantern Green", "libraryId": 7}]"#.utf8))
            }
            if path == "/api/Series/312" {
                return (200, Data(#"{"id": 312, "name": "Lantern Green", "libraryId": 7}"#.utf8))
            }
            if path.hasSuffix("Series/volumes") {
                if calls.next() < failures { return (500, Data()) }
                let volumes = #"[{"id": 55, "number": 1, "chapters": [{"id": 3103, "number": "43", "pages": 22}]}]"#
                return (200, Data(volumes.utf8))
            }
            return (404, Data())
        }
        let address = KavitaAddress(base: try #require(URL(string: "http://\(host)")), apiKey: "key")
        return KavitaClient(address: address, configuration: configuration)
    }

    @Test("A series whose volumes call fails twice is reported, not silently emptied")
    func failsTwiceIsReported() async throws {
        let page = try await KavitaContributor.page(source: UUID(), client: try client(failures: 2), page: 1)

        #expect(page.slice.publications.isEmpty)
        #expect(page.failedSeriesIDs == [312])
        // The page still counted the series as read: the server's own page cursor moved
        // past it, so asking for the same page again is not this page's job.
        #expect(page.seriesRead == 1)
    }

    @Test("A series whose volumes call fails only once still lands in the page, failing nobody")
    func failsOnceStillLands() async throws {
        let page = try await KavitaContributor.page(source: UUID(), client: try client(failures: 1), page: 1)

        #expect(page.slice.publications.count == 1)
        #expect(page.failedSeriesIDs.isEmpty)
    }

    @Test("Retry succeeds once the server does, and drops the series from what still fails")
    func retrySucceeds() async throws {
        let result = await KavitaContributor.retry(source: UUID(), client: try client(failures: 0), seriesIDs: [312])

        #expect(result.publications.count == 1)
        #expect(result.publications.first?.displayTitle == "Lantern Green #43")
        #expect(result.stillFailed.isEmpty)
    }

    @Test("A series the server still refuses stays in what failed, not in the library")
    func retryStillFails() async throws {
        let result = await KavitaContributor.retry(source: UUID(), client: try client(failures: .max), seriesIDs: [312])

        #expect(result.publications.isEmpty)
        #expect(result.stillFailed == [312])
    }

    @Test("retriedOnceOrNil tells a failure from a real empty answer, which a single try? cannot")
    func retriedOnceOrNilDistinguishesFailureFromEmpty() async {
        var calls = 0
        let failedTwice: [Int]? = await KavitaContributor.retriedOnceOrNil {
            calls += 1
            throw URLError(.badServerResponse)
        }

        #expect(calls == 2)
        #expect(failedTwice == nil)
    }
}
