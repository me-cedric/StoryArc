public import Foundation

internal import StoryArcCore

/// The 30-day retention `sources` promises, actually kept.
///
/// `SourceRegistry.collectingExpiredTombstones` existed and was unit-tested and had no
/// production caller on either platform — 10.12. A removed source's tombstone, and the
/// reading positions it was meant to gate, lived forever: nothing ever asked whether thirty
/// days had passed.
extension LibraryModel {
    /// Collects every tombstone thirty days old or older, and forgets the reading
    /// positions nothing else still needs.
    ///
    /// A publication's progress survives the purge when *this device's current shelf*
    /// still holds the same identity under a different, still-configured source — ADR-0006
    /// forbids losing a position by accident, and ``PublicationIdentity/matches(_:)`` is
    /// the same rule `adopt(_:from:)` already uses to decide the two are one book.
    public func purgeExpiredTombstones(at moment: Date = .now) async {
        let (pruned, expired) = registry.collectingExpiredTombstones(at: moment)
        guard !expired.isEmpty else { return }
        registry = pruned
        sourceStore?.save(registry)

        let stillHeld = publications.map(\.identity)
        for tombstone in expired {
            for identity in tombstone.identities where !stillHeld.contains(where: identity.matches) {
                try? await progressStore?.forget(identity)
            }
        }
    }
}
