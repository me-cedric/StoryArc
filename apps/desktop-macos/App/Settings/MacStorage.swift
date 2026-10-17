import Foundation
import StoryArcCore

/// What the app keeps on this Mac, store by store, and whether the disk has room.
///
/// `desktop-experience`, *Storage on a desktop*. Three stores, each measured and cleared on
/// its own: downloads (the download store's directory, in Application Support with the
/// backup exclusion), covers and cached pages (the container's Caches), and the library's
/// records (the reading positions and history). None sits in a folder the system syncs
/// between machines: all three are inside the app's own container (`design.md` Decision 8).
/// The disk is full when the volume has less than `StorageHeadroom`'s reserve left, or when
/// a write has just failed for want of room; the cache is what is offered, because every
/// byte of it can be drawn again. Nothing is cleared without the reader asking.
@MainActor
@Observable
final class MacStorage {
    enum Store: String, CaseIterable, Sendable {
        case downloads, covers, records
    }

    struct Sizes: Equatable, Sendable {
        var downloads: Int64
        var covers: Int64
        var records: Int64

        static let zero = Sizes(downloads: 0, covers: 0, records: 0)

        subscript(store: Store) -> Int64 {
            switch store {
            case .downloads: downloads
            case .covers: covers
            case .records: records
            }
        }
    }

    private(set) var sizes = Sizes.zero
    private(set) var isFull = false
    /// Sizes to show instead of measuring, for the screen catalogue, whose images must not
    /// follow what an earlier walk left in the container. Nil in the app.
    @ObservationIgnored var pinned: Sizes?

    @ObservationIgnored private let measure: () async -> Sizes
    @ObservationIgnored private let freeBytes: () -> Int64?
    @ObservationIgnored private let clearing: (Store) async -> Void
    @ObservationIgnored private var lastWriteWasFull = false

    init(
        measure: @escaping () async -> Sizes, freeBytes: @escaping () -> Int64?,
        clear: @escaping (Store) async -> Void
    ) {
        self.measure = measure
        self.freeBytes = freeBytes
        clearing = clear
    }

    /// The store to offer clearing when the disk is full: the cache, which costs nothing to lose.
    var offersToClear: Store? { isFull ? .covers : nil }

    func refresh() async {
        if let pinned {
            sizes = pinned
            isFull = false
            return
        }
        sizes = await measure()
        isFull = StorageHeadroom.isLow(free: freeBytes()) || (lastWriteWasFull && freeBytes() == nil)
    }

    /// Clears one store, which the reader confirmed, and measures again.
    func clear(_ store: Store) async {
        await clearing(store)
        lastWriteWasFull = false
        await refresh()
    }

    /// Notes a write that failed. True when it failed because the disk is full.
    @discardableResult
    func noteWriteFailure(_ error: any Error) -> Bool {
        let full = Self.isOutOfSpace(error)
        if full {
            lastWriteWasFull = true
            isFull = true
        }
        return full
    }

    static func isOutOfSpace(_ error: any Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
        if let posix = error as? POSIXError, posix.code == .ENOSPC || posix.code == .EDQUOT { return true }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isOutOfSpace(underlying) }
        return false
    }
}
