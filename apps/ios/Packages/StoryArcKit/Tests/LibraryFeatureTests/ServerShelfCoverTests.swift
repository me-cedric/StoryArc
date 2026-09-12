import Foundation
import Kavita
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which members of a server's shelf its composite is built from.
///
/// **These cases used to assert their own arithmetic.** Each one built a tuple array and
/// re-implemented the sort, the prefix and the map inside the test body, so the only thing it
/// touched in the app was the constant `CompositeCover.tileCount`. An adversarial read of the
/// change on 2026-09-12 measured it: changing the view's own `prefix` to 3 left all three
/// cases green. The rule now lives in ``ServerShelfTiles``, outside the view, and these call
/// it — so the same mutation fails here.
struct ServerShelfCoverTests {

    /// Decoded rather than constructed: the type has only a `Decodable` initialiser, which is
    /// the shape a server's answer arrives in and the shape worth testing against.
    private func item(order: Int, chapter: Int) -> KavitaReadingListItem {
        let json = Data(#"{"id": \#(chapter), "order": \#(order), "chapterId": \#(chapter)}"#.utf8)
        // A fixture this test wrote itself, so a failure to decode it is this file's own fault
        // and should stop the run rather than be reported as a shelf defect.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(KavitaReadingListItem.self, from: json)
    }

    @Test("A reading list composites its first four entries, in the reader's order")
    func fourTiles() {
        let items = (11...20).map { item(order: $0, chapter: $0) }

        #expect(ServerShelfTiles.of(items: items) == ["11", "12", "13", "14"])
    }

    /// The reader's order, not the server's listing order, which is the half a prefix alone
    /// would get wrong.
    @Test("A reading list sorts before it takes, so a reordered list composites its own first")
    func orderBeatsListing() {
        let items = [item(order: 9, chapter: 90), item(order: 1, chapter: 10), item(order: 5, chapter: 50)]

        #expect(ServerShelfTiles.of(items: items) == ["10", "50", "90"])
    }

    @Test("Fewer than four entries hand the composite what there is")
    func fewerThanFour() {
        let items = [item(order: 1, chapter: 11), item(order: 0, chapter: 12)]

        #expect(ServerShelfTiles.of(items: items) == ["12", "11"])
    }

    @Test("A shelf with nothing in it asks for no artwork")
    func nothingInIt() {
        #expect(ServerShelfTiles.of(items: []).isEmpty)
        #expect(ServerShelfTiles.of(series: []).isEmpty)
    }

    /// A collection has no order of its own, so the server's listing is the order.
    @Test("A collection takes the server's own order and names its series")
    func collectionKeepsServerOrder() {
        let series = [7, 3, 9, 1, 5].map { KavitaSeries(id: $0, name: "Series \($0)", libraryId: 1) }

        #expect(ServerShelfTiles.of(series: series) == ["7", "3", "9", "1"])
    }

    /// **The whole routing table, which nothing stated before.** A collection asked the
    /// reading-list route for its own locked cover until 2026-09-12. Nothing caught it because
    /// nothing exercised this card, and the choice lived inside a view where no test could
    /// reach it.
    @Test("Each tile of each kind of shelf comes from its own route")
    func everyArtworkRoute() {
        let locked = ServerShelfCardView.serverCoverID

        #expect(ServerShelfArtwork.route(for: locked, isList: true, shelf: 7) == .shelfCoverOfList(7))
        #expect(ServerShelfArtwork.route(for: locked, isList: false, shelf: 7) == .shelfCoverOfCollection(7))
        #expect(ServerShelfArtwork.route(for: "42", isList: true, shelf: 7) == .chapter(42))
        #expect(ServerShelfArtwork.route(for: "42", isList: false, shelf: 7) == .series(42))
    }

    /// An id that names neither asks for nothing. Guessing would fetch some other shelf's art.
    @Test("An id that is not a number and not the locked cover asks for nothing")
    func anUnknownIdAsksForNothing() {
        #expect(ServerShelfArtwork.route(for: "not-a-number", isList: true, shelf: 7) == .nothing)
        #expect(ServerShelfArtwork.route(for: "", isList: false, shelf: 7) == .nothing)
    }
}
