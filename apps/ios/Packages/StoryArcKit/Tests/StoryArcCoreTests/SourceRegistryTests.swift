import Foundation
import Testing

@testable import StoryArcCore

/// The source registry: order, renaming, removal, and the thirty days that follow it.
///
/// The retention half carries the risk. `sources` requires reading progress to outlive a
/// removed source by 30 days, and losing a reading position is the one thing ADR-0006
/// says the app must never do. So the clock is a parameter here rather than `Date()` —
/// a test that waits thirty days is a test nobody runs. Android's `SourceRegistryTest`
/// asserts the same table.
@Suite("Source registry")
struct SourceRegistryTests {

    private func source(_ name: String, kind: SourceKind = .localFolder) -> Source {
        Source(displayName: name, kind: kind)
    }

    // MARK: - Order

    @Test("A new source goes to the end, because the order is the reader's")
    func addsAtTheEnd() {
        let first = source("Comics")
        let second = source("Books")

        let registry = SourceRegistry().adding(first).adding(second)

        #expect(registry.sources.map(\.displayName) == ["Comics", "Books"])
    }

    @Test("Adding the same source twice does not list it twice")
    func addingIsIdempotent() {
        let only = source("Comics")

        let registry = SourceRegistry().adding(only).adding(only)

        #expect(registry.sources.count == 1)
    }

    @Test("A drag downwards lands where the drag reported, not one place early")
    func movesDown() {
        // The destination a drag reports is an index in the list *before* the move.
        // Removing first and inserting at that index lands one place early every time.
        let first = source("A")
        let second = source("B")
        let third = source("C")
        let registry = SourceRegistry().adding(first).adding(second).adding(third)

        let moved = registry.moving(first.id, to: 2)

        #expect(moved.sources.map(\.displayName) == ["B", "A", "C"])
    }

    @Test("A drag upwards lands where the drag reported")
    func movesUp() {
        let first = source("A")
        let second = source("B")
        let third = source("C")
        let registry = SourceRegistry().adding(first).adding(second).adding(third)

        let moved = registry.moving(third.id, to: 0)

        #expect(moved.sources.map(\.displayName) == ["C", "A", "B"])
    }

    @Test("A destination past the end clamps rather than crashing")
    func movePastTheEndClamps() {
        let first = source("A")
        let registry = SourceRegistry().adding(first).adding(source("B"))

        #expect(registry.moving(first.id, to: 99).sources.map(\.displayName) == ["B", "A"])
    }

    // MARK: - Renaming

    @Test("Renaming keeps the source's identity, so everything referring to it follows")
    func renames() {
        let only = source("Comcis")
        let registry = SourceRegistry().adding(only).renaming(only.id, to: "Comics")

        #expect(registry[only.id]?.displayName == "Comics")
        #expect(registry[only.id]?.id == only.id)
    }

    @Test("A blank name is refused, because the name appears inside sentences")
    func refusesABlankName() {
        // `sources`: the name appears "everywhere the source is referenced, including
        // download attributions and error messages". A blank one reads as a missing word.
        let only = source("Comics")
        let registry = SourceRegistry().adding(only)

        #expect(registry.renaming(only.id, to: "   ").sources == registry.sources)
    }

    @Test("A name is stored trimmed")
    func trimsAName() {
        let only = source("x")
        let registry = SourceRegistry().adding(only).renaming(only.id, to: "  Comics\n")

        #expect(registry[only.id]?.displayName == "Comics")
    }

    // MARK: - Removal and the thirty days

    @Test("Removal takes the source out and leaves a tombstone behind")
    func removeLeavesATombstone() {
        let only = source("Kavita", kind: .kavitaServer)
        let moment = Date(timeIntervalSince1970: 1_000_000)

        let registry = SourceRegistry().adding(only).removing(only.id, at: moment)

        #expect(registry.sources.isEmpty)
        #expect(registry.tombstones.map(\.sourceID) == [only.id])
    }

    @Test("Progress is not collectable the day before the thirty are up")
    func notYetExpired() {
        let only = source("Kavita")
        let removed = Date(timeIntervalSince1970: 0)
        let registry = SourceRegistry().adding(only).removing(only.id, at: removed)

        let (after, expired) = registry.collectingExpiredTombstones(
            at: removed.addingTimeInterval(SourceTombstone.retention - 1)
        )

        #expect(expired.isEmpty)
        #expect(after.tombstones.count == 1)
    }

    @Test("Progress is collectable once the thirty days are up")
    func expiresAfterThirtyDays() {
        let only = source("Kavita")
        let removed = Date(timeIntervalSince1970: 0)
        let registry = SourceRegistry().adding(only).removing(only.id, at: removed)

        let (after, expired) = registry.collectingExpiredTombstones(
            at: removed.addingTimeInterval(SourceTombstone.retention)
        )

        #expect(expired == [only.id])
        #expect(after.tombstones.isEmpty)
    }

    @Test("Re-adding a source inside the thirty days keeps its progress")
    func readdingClearsTheTombstone() {
        // The promise `sources` makes: "re-adding the same source restores where the user
        // stopped". It is only true if the tombstone goes, otherwise the collection pass
        // deletes the progress of a source the reader is using again.
        let only = source("Kavita")
        let removed = Date(timeIntervalSince1970: 0)

        let registry = SourceRegistry()
            .adding(only)
            .removing(only.id, at: removed)
            .readding(only)

        let (_, expired) = registry.collectingExpiredTombstones(
            at: removed.addingTimeInterval(SourceTombstone.retention * 2)
        )

        #expect(registry.tombstones.isEmpty)
        #expect(expired.isEmpty)
        #expect(registry[only.id] != nil)
    }

    @Test("Collecting one expired tombstone leaves a younger one alone")
    func collectsOnlyTheExpired() {
        let old = source("Old")
        let recent = source("Recent")
        let start = Date(timeIntervalSince1970: 0)
        let registry = SourceRegistry()
            .adding(old)
            .adding(recent)
            .removing(old.id, at: start)
            .removing(recent.id, at: start.addingTimeInterval(SourceTombstone.retention))

        let (after, expired) = registry.collectingExpiredTombstones(
            at: start.addingTimeInterval(SourceTombstone.retention + 1)
        )

        #expect(expired == [old.id])
        #expect(after.tombstones.map(\.sourceID) == [recent.id])
    }

    @Test("Removing a source that is not there changes nothing")
    func removingAnUnknownSourceIsInert() {
        let registry = SourceRegistry().adding(source("Comics"))

        #expect(registry.removing(UUID(), at: Date()) == registry)
    }
}
