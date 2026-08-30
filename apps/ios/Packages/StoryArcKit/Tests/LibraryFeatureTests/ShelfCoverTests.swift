import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which covers a reading list stands behind.
///
/// `collections-and-reading-lists` writes the rule for a collection — "a composite of its
/// first four member covers" — and ``CompositeCover`` implements it. A reading list needs
/// the same picture and cannot use the same rule: a collection is a set, ordered by identity
/// so that sorting the library does not rearrange the artwork, and a list's order is the
/// thing it exists to hold.
///
/// Android's `shelfTiles` answers these cases identically. Two apps that composed a shelf
/// differently would be one product wearing two faces, which is the divergence this suite
/// exists to catch.
@Suite("Shelf tiles")
struct ShelfCoverTests {

    private func list(_ entries: [String]) -> ReadingList {
        ReadingList(name: "Crossover", entries: entries)
    }

    @Test("A list of four or more shows its first four, in its own order")
    func fourInListOrder() {
        let entries = ["zulu", "alpha", "mike", "bravo", "kilo"]
        #expect(ShelfCover.tiles(of: list(entries)) == ["zulu", "alpha", "mike", "bravo"])
    }

    @Test("Exactly four is the quadrant, not the single cover")
    func exactlyFour() {
        #expect(ShelfCover.tiles(of: list(["a", "b", "c", "d"])).count == CompositeCover.tileCount)
    }

    @Test("Fewer than four shows one cover across the frame, never a quadrant with a hole")
    func fewerThanFour() {
        #expect(ShelfCover.tiles(of: list(["a", "b", "c"])) == ["a"])
        #expect(ShelfCover.tiles(of: list(["only"])) == ["only"])
    }

    @Test("An empty list has nothing to draw, and says so rather than guessing")
    func empty() {
        #expect(ShelfCover.tiles(of: list([])).isEmpty)
    }

    @Test("Reordering a list redraws it, because the order is what it means")
    func reordering() {
        let before = list(["a", "b", "c", "d", "e"])
        let after = ReadingList(id: before.id, name: before.name, entries: ["e", "a", "b", "c", "d"])
        #expect(ShelfCover.tiles(of: before) != ShelfCover.tiles(of: after))
    }

    /// A collection with the same members in a different insertion order composes the same
    /// cover, which is exactly what a reading list must not do.
    @Test("A collection is ordered by identity, so sorting the library leaves it alone")
    func collectionIsStable() {
        let one = PublicationCollection(name: "Set", members: ["d", "a", "c", "b"])
        let two = PublicationCollection(name: "Set", members: ["b", "c", "a", "d"])
        #expect(CompositeCover.tiles(of: one) == CompositeCover.tiles(of: two))
        #expect(CompositeCover.tiles(of: one) == ["a", "b", "c", "d"])
    }
}

/// How far through an ordered shelf the card's rail says the reader is.
@Suite("Shelf progress")
struct ShelfProgressTests {

    @Test("Nothing read is no rail at all")
    func nothingRead() {
        #expect(ShelfProgress(done: 0, total: 6).fraction == 0)
    }

    @Test("A finished list fills the rail exactly once")
    func finished() {
        #expect(ShelfProgress(done: 6, total: 6).fraction == 1)
    }

    @Test("An empty list is not a division by nought")
    func emptyList() {
        #expect(ShelfProgress(done: 0, total: 0).fraction == 0)
    }

    /// The card counts what ``ReadingList/position(finished:)`` counts — everything before
    /// the first unfinished entry — so a reader who skipped ahead is not told they are
    /// further along than they are.
    @Test("Skipping ahead does not move the rail")
    func skippedAhead() {
        let entries = ["a", "b", "c", "d"]
        let list = ReadingList(name: "List", entries: entries)
        let finished: Set<String> = ["d"]
        let done = list.position { finished.contains($0) }
        #expect(ShelfProgress(done: done, total: entries.count).fraction == 0)
    }
}
