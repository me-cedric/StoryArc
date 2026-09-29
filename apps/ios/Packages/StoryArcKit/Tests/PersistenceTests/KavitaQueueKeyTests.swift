import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// The key a held Kavita write is queued under.
///
/// Two servers can each hold a chapter numbered 12 — Kavita numbers chapters per server, not
/// globally — so a key that named only the chapter would let one server's held write erase
/// the other's. Android's `KavitaQueueKeyTest` asserts the same cases.
@Suite("The key a held Kavita write is queued under")
struct KavitaQueueKeyTests {

    private func store(_ name: String = "kavita-queue-\(UUID().uuidString)") -> KavitaProgressStore {
        KavitaProgressStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    private func origin(sourceId: String, chapterId: Int = 12) -> KavitaOrigin {
        KavitaOrigin(sourceId: sourceId, libraryId: 1, seriesId: 7, volumeId: 3, chapterId: chapterId)
    }

    @Test("A held position names its server, so the same chapter on two servers holds twice")
    func twoServersHoldSeparately() {
        let store = store()
        store.hold(KavitaUnsent(origin: origin(sourceId: "server-a"), page: 4))
        store.hold(KavitaUnsent(origin: origin(sourceId: "server-b"), page: 9))

        #expect(store.unsent().count == 2)
        #expect(Set(store.unsent().map(\.page)) == [4, 9])
    }

    @Test("A later position on the same server for the same chapter replaces the held one")
    func sameServerAndChapterReplaces() {
        let store = store()
        store.hold(KavitaUnsent(origin: origin(sourceId: "server-a"), page: 4))
        store.hold(KavitaUnsent(origin: origin(sourceId: "server-a"), page: 9))

        #expect(store.unsent().count == 1)
        #expect(store.unsent().first?.page == 9)
    }

    @Test("Dropping one server's key leaves the other server's held entry alone")
    func dropIsScopedToItsKey() {
        let store = store()
        let onA = KavitaUnsent(origin: origin(sourceId: "server-a"), page: 4)
        let onB = KavitaUnsent(origin: origin(sourceId: "server-b"), page: 9)
        store.hold(onA)
        store.hold(onB)

        store.drop(onA.key)

        #expect(store.unsent() == [onB])
    }
}
