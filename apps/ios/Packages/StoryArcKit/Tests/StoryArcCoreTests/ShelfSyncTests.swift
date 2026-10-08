import Foundation
import Testing
@testable import StoryArcCore

/// `library-sync` tasks 3.3 and 3.4: shelves merge their members, and a deletion travels.
/// Android's `ShelfSyncTest` makes the same claims.
struct ShelfSyncTests {

    private let shelf = LibraryDocumentFixture.fixed("CCCCCCCC-0000-0000-0000-000000000003")
    private let list = LibraryDocumentFixture.fixed("DDDDDDDD-0000-0000-0000-000000000004")

    private func shared() -> LibrarySnapshot {
        LibrarySnapshot(shelves: Shelves(
            collections: [PublicationCollection(id: shelf, name: "Image", members: ["a"], changedAt: moment(1))],
            lists: [ReadingList(id: list, name: "Crossover", entries: ["a"], changedAt: moment(1))]
        ))
    }

    /// The reader's own change on a device, stamped as the store stamps it.
    private func change(_ device: SyncDevice, at second: TimeInterval, _ edit: (Shelves) -> Shelves) {
        let stamped = ShelfStamps.stamped(
            before: device.library.shelves, removedBefore: device.library.removedShelves,
            after: edit(device.library.shelves), removedAfter: device.library.removedShelves,
            now: moment(second)
        )
        device.library.shelves = stamped.shelves
        device.library.removedShelves = stamped.removed
    }

    @Test func membersTwoDevicesAddedToOneShelfBothArrive() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shared())
        let deviceB = SyncDevice("device-b", shared())
        change(deviceA, at: 2) { $0.adding(["from-a"], to: shelf) }
        change(deviceB, at: 3) { $0.adding(["from-b"], to: shelf) }

        try await deviceA.sync(place, at: 4)
        try await deviceB.sync(place, at: 5)
        try await deviceA.sync(place, at: 6)

        for device in [deviceA, deviceB] {
            #expect(device.library.shelves.collections.first?.members == ["a", "from-a", "from-b"])
        }
    }

    @Test func aReadingListKeepsTheOlderSidesOrderFirst() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shared())
        let deviceB = SyncDevice("device-b", shared())
        change(deviceA, at: 2) { $0.appending(["a2", "a3"], to: list) }
        change(deviceB, at: 3) { $0.appending(["b2"], to: list) }

        try await deviceA.sync(place, at: 4)
        try await deviceB.sync(place, at: 5)
        try await deviceA.sync(place, at: 6)

        #expect(deviceA.library.shelves.lists.first?.entries == ["a", "a2", "a3", "b2"])
        #expect(deviceB.library.shelves.lists.first?.entries == ["a", "a2", "a3", "b2"])
    }

    @Test func theNameChangedLastWins() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shared())
        let deviceB = SyncDevice("device-b", shared())
        change(deviceA, at: 3) { $0.renaming(collection: shelf, to: "Image Comics") }
        change(deviceB, at: 2) { $0.renaming(collection: shelf, to: "Older name") }

        try await deviceA.sync(place, at: 4)
        try await deviceB.sync(place, at: 5)

        #expect(deviceB.library.shelves.collections.first?.name == "Image Comics")
    }

    @Test func aShelfDeletedOnOneDeviceIsGoneOnTheOtherAndStaysGone() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shared())
        let deviceB = SyncDevice("device-b", shared())
        try await deviceA.sync(place, at: 2)
        try await deviceB.sync(place, at: 3)

        change(deviceA, at: 4) { $0.deleting(collection: shelf).deleting(list: list) }
        try await deviceA.sync(place, at: 5)
        try await deviceB.sync(place, at: 6)
        try await deviceA.sync(place, at: 7)
        try await deviceB.sync(place, at: 8)

        for device in [deviceA, deviceB] {
            #expect(device.library.shelves.collections.isEmpty)
            #expect(device.library.shelves.lists.isEmpty)
        }
        let removed = try place.document().library.removedShelves ?? []
        #expect(Set(removed.map(\.id)) == [shelf, list])
        #expect(removed.allSatisfy { $0.removedBy == "device-a" })
    }

    @Test func aShelfChangedAfterTheDeletionComesBack() async throws {
        let place = MemoryPlace()
        let deviceA = SyncDevice("device-a", shared())
        let deviceB = SyncDevice("device-b", shared())
        change(deviceA, at: 4) { $0.deleting(collection: shelf) }
        change(deviceB, at: 6) { $0.adding(["later"], to: shelf) }

        try await deviceA.sync(place, at: 7)
        try await deviceB.sync(place, at: 8)
        try await deviceA.sync(place, at: 9)

        #expect(deviceA.library.shelves.collections.first?.members == ["a", "later"])
        #expect(!deviceA.library.removedShelves.contains { $0.id == shelf })
    }

    @Test func aStoreRecordsADeletionAndStampsAChange() {
        let before = shared().shelves
        let after = before.deleting(list: list).renaming(collection: shelf, to: "Renamed")

        let stamped = ShelfStamps.stamped(
            before: before, removedBefore: [], after: after, removedAfter: [], now: moment(9)
        )

        #expect(stamped.removed == [ShelfTombstone(id: list, removedAt: moment(9))])
        #expect(stamped.shelves.collections.first?.changedAt == moment(9))
    }

    @Test func aMomentAMergeBroughtIsKeptAndAShelfPutBackLosesItsTombstone() {
        let before = shared().shelves
        var renamed = before.collections[0]
        renamed.name = "From B"
        renamed.changedAt = moment(5)
        let merged = Shelves(collections: [renamed], lists: before.lists)
        let kept = ShelfStamps.stamped(
            before: before, removedBefore: [], after: merged, removedAfter: [], now: moment(9)
        )
        #expect(kept.shelves.collections.first?.changedAt == moment(5))

        let gone = ShelfStamps.stamped(
            before: before, removedBefore: [],
            after: before.deleting(collection: shelf), removedAfter: [], now: moment(10)
        )
        let back = ShelfStamps.stamped(
            before: gone.shelves, removedBefore: gone.removed,
            after: before, removedAfter: gone.removed, now: moment(11)
        )
        #expect(back.shelves.collections.first?.changedAt == moment(11))
        #expect(!back.removed.contains { $0.id == shelf })
    }
}
