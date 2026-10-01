import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A report that reaches the server drops what an earlier, offline read had held.
///
/// The field defect: an offline read holds page 10; an online session later reports page 20;
/// a subsequent flush still sends the held page 10 and moves the server back. Android's
/// `KavitaSyncQueueTest` asserts the same case.
/// A box, mutated from a `@Sendable` callback and read back on the test's own task — never
/// from two places at once, so `@unchecked` is honest. `ShelfOrderConflictTests`' own `Flag`
/// is the same shape, private to that file.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

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

    @Test("A successful report stamps the local record as synchronised")
    func successStampsSyncedPosition() async throws {
        let store = store()
        let origin = origin()
        let progress = try ProgressStore.inMemory()
        let identity = PublicationIdentity(normalizedPath: "/books/\(UUID().uuidString).cbz")
        store.remember(origin, for: identity.stableID)
        try await progress.save(
            ReadingProgress(identity: identity, position: .page(index: 19, of: 20), updatedAt: .now)
        )

        let (address, configuration) = try acceptingAddress(host: "\(UUID().uuidString).sync-stamp.test")
        await KavitaSync.report(
            19, for: origin, to: address, in: store, progress: progress, configuration: configuration
        )

        let found = try await progress.progress(for: identity)
        #expect(found?.syncedPosition == .page(index: 19, of: 20))
    }

    @Test("A finished local record that wins a conflict is queued as a mark, not a page")
    func finishedLocalRecordQueuesAMark() async throws {
        let store = store()
        let chapterOrigin = origin()
        let progress = try ProgressStore.inMemory()
        let identity = PublicationIdentity(normalizedPath: "/books/\(UUID().uuidString).cbz")
        store.remember(chapterOrigin, for: identity.stableID)
        try await progress.save(
            ReadingProgress(
                identity: identity,
                position: .page(index: 9, of: 10),
                isFinished: true,
                updatedAt: .now
            )
        )

        // No address: the queue is the whole assertion here, not a network round trip.
        await KavitaSync.pull(
            [KavitaChapter(id: chapterOrigin.chapterId, number: "1", pages: 10, pagesRead: 2)],
            in: store,
            into: progress
        )

        let held = try #require(store.unsent().first)
        #expect(held.mark == true)
        #expect(held.origin.chapterId == chapterOrigin.chapterId)
    }

    @Test("A pull that reaches its server sends what was held, even with nothing owed")
    func pullFlushesWithNothingOwed() async throws {
        // The library's own refresh is a pull. A held write waited for the chapter screen
        // before, because a pull flushed only when its own merge owed the server something.
        let store = store()
        let origin = origin()
        store.hold(KavitaUnsent(origin: origin, page: 4))

        let (address, configuration) = try acceptingAddress(host: "\(UUID().uuidString).sync-refresh.test")
        await KavitaSync.pull(
            [], in: store, into: try ProgressStore.inMemory(),
            of: origin.sourceId, to: address, configuration: configuration
        )

        #expect(store.unsent().isEmpty, "the held write must go out on the refresh")
    }

    @Test("A held position stamps its local record too, once flush delivers it")
    func flushStampsSyncedPosition() async throws {
        let store = store()
        let origin = origin()
        let progress = try ProgressStore.inMemory()
        let identity = PublicationIdentity(normalizedPath: "/books/\(UUID().uuidString).cbz")
        store.remember(origin, for: identity.stableID)
        try await progress.save(
            ReadingProgress(identity: identity, position: .page(index: 9, of: 10), updatedAt: .now)
        )
        store.hold(KavitaUnsent(origin: origin, page: 9))

        let (address, configuration) = try acceptingAddress(host: "\(UUID().uuidString).sync-flush.test")
        _ = await KavitaSync.flush(
            origin.sourceId, to: address, in: store, progress: progress, configuration: configuration
        )

        let found = try await progress.progress(for: identity)
        #expect(found?.syncedPosition == .page(index: 9, of: 10))
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

    /// A server old enough to lack `mark-multiple-*`.
    private func routeMissingAddress(host: String) throws -> (KavitaAddress, URLSessionConfiguration) {
        let address = KavitaAddress(base: try #require(URL(string: "http://\(host)")), apiKey: "key")
        let configuration = EntryStub.session(host: host) { request in
            request.url?.path().hasSuffix("Plugin/authenticate") == true
                ? (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
                : (404, Data())
        }
        return (address, configuration)
    }

    @Test("D2: a mark sent now, refused with a 404, is not held for a retry that can never land")
    func immediateMarkDropsOnRouteMissing() async throws {
        let store = store()
        let origin = origin()
        let (address, configuration) = try routeMissingAddress(host: "\(UUID().uuidString).mark-missing.test")
        let toldMissing = Box(false)

        await KavitaSync.mark(
            true, for: origin, to: address, in: store, configuration: configuration
        ) { toldMissing.value = true }

        #expect(toldMissing.value)
        #expect(store.unsent().isEmpty, "a route the server will never grow must not be retried forever")
    }

    @Test("D2: a held mark a flush finds refused leaves the queue and is reported, not retried")
    func flushDropsAHeldMarkOnRouteMissing() async throws {
        let store = store()
        let origin = origin()
        store.hold(KavitaUnsent(origin: origin, page: 0, mark: true))
        let (address, configuration) = try routeMissingAddress(host: "\(UUID().uuidString).flush-missing.test")
        let reported = Box<KavitaUnsent?>(nil)

        _ = await KavitaSync.flush(
            origin.sourceId, to: address, in: store, configuration: configuration,
            onRouteMissing: { reported.value = $0 }
        )

        #expect(reported.value?.origin.chapterId == origin.chapterId)
        #expect(store.unsent().isEmpty)
    }

    @Test("Task 12.6: deleting a shelf holds the deletion when the server is away")
    func deleteShelfHoldsWhenUnreachable() async {
        let store = store()
        await KavitaSync.deleteShelf(9, isCollection: true, on: "a-server", to: nil, in: store)

        let held = store.unsent().first
        #expect(held?.listID == 9)
        #expect(held?.deleteShelf == true)
    }

    @Test("Task 12.6: deleting a shelf reaches a reachable server and leaves nothing held")
    func deleteShelfSendsWhenReachable() async throws {
        let store = store()
        let (address, configuration) = try acceptingAddress(host: "\(UUID().uuidString).delete-shelf.test")

        await KavitaSync.deleteShelf(
            9, isCollection: false, on: "a-server", to: address, in: store, configuration: configuration
        )

        #expect(store.unsent().isEmpty)
    }

    @Test("Task 12.6: removing a list entry holds the removal when the server is away")
    func removeEntryHoldsWhenUnreachable() async {
        let store = store()
        await KavitaSync.removeEntry(3, at: 1, from: 9, on: "a-server", to: nil, in: store)

        let held = store.unsent().first
        #expect(held?.listID == 9)
        #expect(held?.removeItemID == 3)
        #expect(held?.removeItemPosition == 1)
    }

    @Test("Task 12.6: removing a list entry reaches a reachable server and leaves nothing held")
    func removeEntrySendsWhenReachable() async throws {
        let store = store()
        let (address, configuration) = try acceptingAddress(host: "\(UUID().uuidString).remove-entry.test")

        await KavitaSync.removeEntry(
            3, at: 1, from: 9, on: "a-server", to: address, in: store, configuration: configuration
        )

        #expect(store.unsent().isEmpty)
    }

    @Test("Task 12.6: a held shelf deletion and a held entry removal are two different promises")
    func deleteShelfAndRemoveEntryCoexist() async {
        let store = store()
        await KavitaSync.deleteShelf(9, isCollection: true, on: "a-server", to: nil, in: store)
        await KavitaSync.removeEntry(3, at: 1, from: 9, on: "a-server", to: nil, in: store)

        #expect(store.unsent().count == 2)
    }

    @Test("A held mark beside a held position: only the mark is refused, and only it leaves")
    func flushRefusesOnlyTheMarkAmongWhatIsHeld() async throws {
        let store = store()
        let origin = origin()
        // The same origin for both: `KavitaUnsent.key` tells a mark from a position by its
        // own `mark` field, so the two coexist in the queue, and both reach the same stub
        // in the same flush — which is what proves the mark's 404 is read as `routeMissing`
        // specifically, and the position's plain 404 is not.
        store.hold(KavitaUnsent(origin: origin, page: 0, mark: true))
        store.hold(KavitaUnsent(origin: origin, page: 5))
        let (address, configuration) = try routeMissingAddress(host: "\(UUID().uuidString).flush-mixed.test")

        _ = await KavitaSync.flush(origin.sourceId, to: address, in: store, configuration: configuration)

        // The position's own 404 is an ordinary failure `send` lets through uncaught, so
        // `flush`'s `catch { continue }` keeps it held — this asserts the mark's departure
        // is `onRouteMissing`'s doing, not a side effect of every held entry leaving
        // regardless of its own kind.
        #expect(store.unsent().count == 1)
        #expect(store.unsent().allSatisfy { $0.mark == nil })
    }
}
