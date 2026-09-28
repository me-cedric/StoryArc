public import StoryArcCore

/// Where a continuous scroll sits within its current page, kept only on this device.
///
/// Not part of `ReadingProgress`: that record is what syncs (ADR-0006), and syncing a
/// sub-page fraction would compare two devices' idea of "the same page" down to a pixel
/// neither shares typography with. `comic-reader` only asks for this to survive
/// "leaving and returning" the reader, which a per-device blob already does, and the
/// stored page index is untouched by it either way.
public struct ScrollOffsetMemory: Sendable, Equatable, Codable {
    private var byIdentity: [String: Double] = [:]

    public init() {}

    /// The fraction stored for a publication, or `nil` when none has been.
    public func fraction(for identity: PublicationIdentity) -> Double? {
        byIdentity[identity.stableID]
    }

    /// This memory, with a publication's fraction set or replaced.
    public func remembering(_ fraction: Double, for identity: PublicationIdentity) -> ScrollOffsetMemory {
        var copy = self
        copy.byIdentity[identity.stableID] = min(1, max(0, fraction))
        return copy
    }
}
