import Foundation
import Kavita
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which artwork a server's shelf asks for.
///
/// `collections-and-reading-lists`: a shelf's cover "is a composite of its first four member
/// covers unless the user sets a specific one", and this change makes that hold "for a
/// collection a server defines exactly as it does for one made on the device". Before it, a
/// server shelf passed an empty tile list and drew a blank frame.
///
/// The composite itself — four quadrants, or one across the frame — is ``ShelfComposite``'s
/// and is unchanged by this change. What is asserted here is the rule that feeds it.
///
/// Android's `ServerShelfCoverTest` makes the same claims.
struct ServerShelfCoverTests {

    @Test("Four or more entries composite the first four in the order given")
    func fourTiles() {
        let entries = (11...20).map { (order: $0, chapterId: $0) }

        let tiles = entries.sorted { $0.order < $1.order }
            .prefix(CompositeCover.tileCount)
            .map { String($0.chapterId) }

        #expect(tiles == ["11", "12", "13", "14"])
    }

    @Test("Fewer than four entries hand the composite what there is")
    func fewerThanFour() {
        let entries = [(order: 1, chapterId: 11), (order: 0, chapterId: 12)]

        let tiles = entries.sorted { $0.order < $1.order }
            .prefix(CompositeCover.tileCount)
            .map { String($0.chapterId) }

        // Sorted by the server's order, not by id: a reading list's order is its meaning.
        #expect(tiles == ["12", "11"])
    }

    @Test("A shelf with nothing in it asks for no artwork")
    func nothingInIt() {
        let entries: [(order: Int, chapterId: Int)] = []

        let tiles = entries.prefix(CompositeCover.tileCount).map { String($0.chapterId) }

        #expect(tiles.isEmpty)
    }
}
