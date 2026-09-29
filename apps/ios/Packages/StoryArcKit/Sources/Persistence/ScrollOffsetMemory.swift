public import StoryArcCore

/// Where a continuous scroll sits within its current page, kept only on this device.
///
/// Not part of `ReadingProgress`: that record is what syncs (ADR-0006), and syncing a
/// sub-page fraction would compare two devices' idea of "the same page" down to a pixel
/// neither shares typography with. `comic-reader` only asks for this to survive
/// "leaving and returning" the reader, which a per-device blob already does, and the
/// stored page index is untouched by it either way.
///
/// **Kept with the page it belongs to.** A fraction on its own was restored onto
/// whichever page the reader opened on: a position synced from another device, or a
/// page turned to in another mode, took the fraction of a page it had never been on.
public struct ScrollOffsetMemory: Sendable, Equatable, Codable {
    /// Where a scroll stopped: the page, and how far through it.
    public struct Entry: Sendable, Equatable, Codable {
        public let page: Int
        public let fraction: Double
    }

    private var byIdentity: [String: Entry] = [:]

    public init() {}

    /// Where a publication's scroll last stopped, or `nil` when it never did.
    public func entry(for identity: PublicationIdentity) -> Entry? {
        byIdentity[identity.stableID]
    }

    /// This memory, with a publication's stopping place set or replaced.
    public func remembering(
        _ fraction: Double, onPage page: Int, for identity: PublicationIdentity
    ) -> ScrollOffsetMemory {
        var copy = self
        copy.byIdentity[identity.stableID] = Entry(page: page, fraction: min(1, max(0, fraction)))
        return copy
    }
}
