import Foundation
import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore
import Testing

/// `library-browsing` (D36): the status a Kavita server reports for a series is carried onto
/// every row the library reads from that series, through
/// ``KavitaContributor/page(source:client:page:store:)``.
///
/// Android's `KavitaContributorStatusTest` makes the same claims.
@Suite("A browsed series' reported status")
struct KavitaContributorStatusTests {

    private func statuses(metadata: String?) async throws -> [PublicationStatus?] {
        let host = "\(UUID().uuidString).contributor-status.test"
        let configuration = EntryStub.session(host: host) { request in
            let path = request.url?.path() ?? ""
            if path.hasSuffix("Plugin/authenticate") {
                return (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
            }
            if path.hasSuffix("Series/recently-added-v2") {
                return (200, Data(#"[{"id": 312, "name": "Lantern Green", "libraryId": 7}]"#.utf8))
            }
            if path.hasSuffix("Series/metadata") {
                return metadata.map { (200, Data($0.utf8)) } ?? (500, Data())
            }
            let volumes = #"[{"id": 55, "number": 1, "chapters": [{"id": 3103, "number": "43", "pages": 22}, "#
                + #"{"id": 3104, "number": "44", "pages": 20}]}]"#
            return (200, Data(volumes.utf8))
        }
        let address = KavitaAddress(base: try #require(URL(string: "http://\(host)")), apiKey: "key")
        let client = KavitaClient(address: address, configuration: configuration)
        let store = KavitaProgressStore(defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))

        let page = try await KavitaContributor.page(source: UUID(), client: client, page: 1, store: store)
        return page.slice.publications.map(\.status)
    }

    @Test("Every chapter row carries the status its server reports for the series")
    func rowsCarryTheReportedStatus() async throws {
        let found = try await statuses(metadata: #"{"seriesId": 312, "publicationStatus": 2}"#)
        #expect(found == [.completed, .completed])
    }

    @Test("A status the server could not give leaves the rows without one, and keeps them")
    func failedStatusKeepsTheRows() async throws {
        let found = try await statuses(metadata: nil)
        #expect(found == [nil, nil])
    }
}
