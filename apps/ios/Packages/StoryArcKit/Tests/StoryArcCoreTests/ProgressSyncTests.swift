import Foundation
import Testing
@testable import StoryArcCore

/// `library-sync` tasks 3.2 and 5.1: reading progress through the sync document, by ADR-0006,
/// between two devices that share one place. Android's `ProgressSyncTest` makes the same claims.
struct ProgressSyncTests {

    private let book = PublicationIdentity(contentDigest: "d1")

    @Test func aSyncStampsThePositionTheDocumentNowHolds() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        deviceA.read(book, page: 40, at: 1)

        try await deviceA.sync(place, at: 2)

        #expect(deviceA.position(book)?.syncedPosition == .page(index: 40, of: 100))
    }

    @Test func afterASyncAFurtherMoveOnTheOtherDeviceArrivesWithNoConflict() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        let deviceB = SyncDevice("device-b")
        deviceA.read(book, page: 10, at: 1)
        try await deviceA.sync(place, at: 2)
        try await deviceB.sync(place, at: 3)
        // A reads on, and the watermark of the first sync is now behind it.
        deviceA.read(book, page: 40, at: 4)
        try await deviceA.sync(place, at: 5)
        try await deviceB.sync(place, at: 6)
        deviceB.read(book, page: 60, at: 7)
        try await deviceB.sync(place, at: 8)

        try await deviceA.sync(place, at: 9)

        #expect(deviceA.position(book)?.position == .page(index: 60, of: 100))
        #expect((deviceA.conflicts + deviceB.conflicts).isEmpty)
    }

    @Test func twoDevicesThatNeverSyncedSettleOnTheFurtherPositionWithNoNotice() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        let deviceB = SyncDevice("device-b")
        deviceA.read(book, page: 40, at: 1)
        deviceB.read(book, page: 20, at: 2)

        try await deviceA.sync(place, at: 3)
        try await deviceB.sync(place, at: 4)
        try await deviceA.sync(place, at: 5)

        #expect(deviceA.position(book)?.position == .page(index: 40, of: 100))
        #expect(deviceB.position(book)?.position == .page(index: 40, of: 100))
        #expect((deviceA.conflicts + deviceB.conflicts).isEmpty)
    }

    @Test func twoDevicesThatBothMovedSinceASharedSyncAreToldOnceNamingBoth() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        let deviceB = SyncDevice("device-b")
        deviceA.read(book, page: 30, at: 1)
        try await deviceA.sync(place, at: 2)
        try await deviceB.sync(place, at: 3)
        deviceA.read(book, page: 40, at: 4)
        deviceB.read(book, page: 50, at: 5)

        try await deviceA.sync(place, at: 6)
        try await deviceB.sync(place, at: 7)
        try await deviceA.sync(place, at: 8)
        try await deviceB.sync(place, at: 9)

        let notices = deviceA.conflicts + deviceB.conflicts
        #expect(notices.count == 1)
        #expect(notices.first?.resolved.position == .page(index: 50, of: 100))
        #expect(notices.first?.discarded == .page(index: 40, of: 100))
        #expect(deviceA.position(book)?.position == .page(index: 50, of: 100))
    }

    @Test func aPublicationFinishedOnOneDeviceStaysFinishedOnBoth() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a")
        let deviceB = SyncDevice("device-b")
        deviceA.read(book, page: 30, at: 1)
        deviceA.library.progress = deviceA.library.progress.map { $0.finished(true, at: moment(2)) }
        deviceB.read(book, page: 45, at: 3)

        try await deviceA.sync(place, at: 4)
        try await deviceB.sync(place, at: 5)
        try await deviceA.sync(place, at: 6)

        #expect(deviceA.position(book)?.isFinished == true)
        #expect(deviceB.position(book)?.isFinished == true)
        #expect(try place.document().library.progress.first?.isFinished == true)
    }
}
