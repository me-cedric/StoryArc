import Foundation
import Testing

@testable import StoryArcCore

@Suite("A collection's composite cover")
struct CompositeCoverTests {
    private func collection(_ members: Set<String>, cover: String? = nil) -> PublicationCollection {
        PublicationCollection(name: "Image Comics", members: members, coverMemberID: cover)
    }

    @Test("A collection with nothing in it has nothing to composite")
    func emptyCollectionHasNoTiles() {
        #expect(CompositeCover.tiles(of: collection([])).isEmpty)
    }

    @Test("One, two or three members show one cover rather than a quadrant with holes")
    func fewerThanFourShowOne() {
        #expect(CompositeCover.tiles(of: collection(["b"])) == ["b"])
        #expect(CompositeCover.tiles(of: collection(["b", "a"])) == ["a"])
        #expect(CompositeCover.tiles(of: collection(["c", "a", "b"])) == ["a"])
    }

    @Test("Four members are the four tiles, by identity ascending")
    func fourMembersFillTheQuadrants() {
        let tiles = CompositeCover.tiles(of: collection(["d", "b", "a", "c"]))
        #expect(tiles == ["a", "b", "c", "d"])
    }

    @Test("A fifth member changes nothing: the first four are the composite")
    func onlyTheFirstFourAreDrawn() {
        let tiles = CompositeCover.tiles(of: collection(["e", "d", "c", "b", "a"]))
        #expect(tiles == ["a", "b", "c", "d"])
        #expect(tiles.count == CompositeCover.tileCount)
    }

    @Test("A cover the reader chose replaces the composite outright")
    func chosenCoverWins() {
        let chosen = collection(["a", "b", "c", "d", "e"], cover: "e")
        #expect(CompositeCover.tiles(of: chosen) == ["e"])
    }

    @Test("A chosen cover that has left the collection is not its cover any more")
    func chosenCoverMustStillBeAMember() {
        let stale = collection(["a", "b", "c", "d"], cover: "z")
        #expect(CompositeCover.tiles(of: stale) == ["a", "b", "c", "d"])
    }
}
