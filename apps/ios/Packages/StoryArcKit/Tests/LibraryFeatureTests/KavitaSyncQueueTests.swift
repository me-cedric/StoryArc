import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import Persistence

/// A report that reaches the server drops what an earlier, offline read had held.
///
/// The field defect: an offline read holds page 10; an online session later reports page 20;
/// a subsequent flush still sends the held page 10 and moves the server back. Android's
/// `KavitaSyncQueueTest` asserts the same case.
@Suite("A successful report clears its own held entry")
struct KavitaSyncQueueTests {

    private func store(_ name: String = "kavita-sync-queue-\(UUID().uuidString)") -> KavitaProgressStore {
        KavitaProgressStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    private func origin(sourceId: String = UUID().uuidString) -> KavitaOrigin {
        KavitaOrigin(sourceId: sourceId, libraryId: 1, seriesId: 7, volumeId: 3, chapterId: 12)
    }

    /// A server that answers every `Reader/progress` post with 200.
    private func acceptingAddress(host: String) throws -> (KavitaAddress, URLSessionConfiguration) {
        let address = KavitaAddress(base: try #require(URL(string: "http://\(host)")), apiKey: "key")
        let configuration = EntryStub.session(host: host) { request in
            request.url?.path().hasSuffix("Plugin/authenticate") == true
                ? (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
                : (200, Data("{}".utf8))
        }
        return (address, configuration)
    }

    @Test("A page held while offline is dropped once the same chapter reports successfully")
    func successDropsTheOlderHeldPage() async throws {
        let store = store()
        let origin = origin()
        // The offline read: page 10 could not reach the server, so it sits in the queue.
        store.hold(KavitaUnsent(origin: origin, page: 10))
        #expect(store.unsent().count == 1)

        // The online session: page 20, reported straight to a server that answers.
        let (address, configuration) = try acceptingAddress(host: "\(UUID().uuidString).sync-drop.test")
        await KavitaSync.report(20, for: origin, to: address, in: store, configuration: configuration)

        #expect(store.unsent().isEmpty, "the stale held page must not survive a successful report")
    }

    @Test("A report that fails still holds its own page, alongside another server's")
    func failureHoldsBesideAnotherServer() async {
        let store = store()
        let other = self.origin(sourceId: "other-server")
        store.hold(KavitaUnsent(origin: other, page: 3))

        // No address at all is the same "not reachable" branch a network failure takes.
        await KavitaSync.report(7, for: origin(sourceId: "this-server"), to: nil, in: store)

        #expect(store.unsent().count == 2)
        #expect(Set(store.unsent().map(\.page)) == [3, 7])
    }
}
