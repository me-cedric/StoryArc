import Foundation
import Testing

@testable import StoryArc

/// Task 3.15: storage in the preferences, each store on its own, and a full disk said in grey.
///
/// `desktop-experience`, *Storage on a desktop*: the sizes of downloads, covers and the
/// library's records, each clearable on its own; a write that fails because the disk is full
/// is named, what the app had is kept, and clearing a cache is offered.
@MainActor
@Suite("Storage")
struct StorageTests {
    /// Three stores in memory, and what was cleared.
    private final class Stores {
        var sizes = MacStorage.Sizes(downloads: 40_000_000, covers: 3_000_000, records: 200_000)
        var cleared: [MacStorage.Store] = []
        var free: Int64? = 50_000_000_000
    }

    private func storage(_ stores: Stores) -> MacStorage {
        MacStorage(
            measure: { stores.sizes },
            freeBytes: { stores.free },
            clear: { store in
                stores.cleared.append(store)
                switch store {
                case .downloads: stores.sizes.downloads = 0
                case .covers: stores.sizes.covers = 0
                case .records: stores.sizes.records = 0
                }
            }
        )
    }

    @Test("Each store shows its own size")
    func sizes() async {
        let stores = Stores()
        let storage = storage(stores)
        await storage.refresh()
        #expect(storage.sizes == stores.sizes)
        #expect(!storage.isFull)
    }

    @Test("Each store is cleared on its own, and the others keep what they hold", arguments: MacStorage.Store.allCases)
    func clearsOne(store: MacStorage.Store) async {
        let stores = Stores()
        let storage = storage(stores)
        await storage.refresh()
        await storage.clear(store)
        #expect(stores.cleared == [store])
        #expect(storage.sizes[store] == 0)
        for other in MacStorage.Store.allCases where other != store {
            #expect(storage.sizes[other] > 0, "\(other) was cleared with \(store)")
        }
    }

    @Test("A volume with less than the reserve left is full, said in grey, and offers the cache")
    func lowVolume() async {
        let stores = Stores()
        stores.free = 10_000_000
        let storage = storage(stores)
        await storage.refresh()
        #expect(storage.isFull)
        #expect(storage.offersToClear == .covers)
        #expect(stores.cleared.isEmpty, "nothing is cleared without the reader asking")
    }

    @Test("A write that failed for want of room is named as a full disk, and another failure is not")
    func writeFailures() {
        let storage = storage(Stores())
        #expect(storage.noteWriteFailure(CocoaError(.fileWriteOutOfSpace)))
        #expect(storage.isFull)
        let other = MacStorage(measure: { .zero }, freeBytes: { nil }, clear: { _ in })
        #expect(other.noteWriteFailure(POSIXError(.ENOSPC)))
        let third = MacStorage(measure: { .zero }, freeBytes: { nil }, clear: { _ in })
        #expect(!third.noteWriteFailure(CocoaError(.fileWriteNoPermission)))
        #expect(!third.isFull)
    }

    @Test("Clearing the cache on a full disk takes the notice away once there is room")
    func clearingFrees() async {
        let stores = Stores()
        stores.free = 10_000_000
        let storage = storage(stores)
        await storage.refresh()
        stores.free = 900_000_000
        await storage.clear(.covers)
        #expect(!storage.isFull)
    }
}
