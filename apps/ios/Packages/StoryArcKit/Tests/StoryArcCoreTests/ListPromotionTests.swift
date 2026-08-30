import Foundation
import Testing

@testable import StoryArcCore

@Suite("Copying a local reading list onto a server")
struct ListPromotionTests {
    /// A list of six, of which the server holds the odd-numbered ones.
    private let entries = ["a", "b", "c", "d", "e", "f"]
    private let held: Set<String> = ["a", "c", "e"]

    private func promotion(_ entries: [String], held: Set<String>) -> ListPromotion {
        ListPromotion(entries: entries) { held.contains($0) }
    }

    @Test("Every entry the server already holds is copied")
    func theServerKeepsWhatItAlreadyHas() {
        #expect(promotion(entries, held: held).copying == ["a", "c", "e"])
    }

    @Test("An entry the server does not hold is left behind, not uploaded")
    func whatTheServerLacksIsLeftBehind() {
        // The whole reason the spec asks the app to say which: there is no backend to push a
        // file to, so a publication the server has never seen cannot join one of its lists.
        #expect(promotion(entries, held: held).leftBehind == ["b", "d", "f"])
    }

    @Test("Both halves keep the list's own order, not the library's")
    func theListsOrderSurvives() {
        // The order is a reading list's whole meaning, so a copy that arrived in some other
        // order would be a different list.
        let reversed = promotion(entries.reversed(), held: held)
        #expect(reversed.copying == ["e", "c", "a"])
        #expect(reversed.leftBehind == ["f", "d", "b"])
    }

    @Test("The count the reader is shown is both halves together")
    func theTotalCountsEverything() {
        let promotion = promotion(entries, held: held)
        #expect(promotion.total == 6)
        #expect(promotion.total == promotion.copying.count + promotion.leftBehind.count)
    }

    @Test("A list the server holds nothing of cannot be copied, and says so before it starts")
    func aServerThatHoldsNoneOfItCannotTakeIt() {
        let promotion = promotion(entries, held: [])
        #expect(!promotion.isPossible)
        #expect(promotion.leftBehind == entries)
    }

    @Test("An empty list has nothing to copy")
    func anEmptyListPromotesNothing() {
        let promotion = promotion([], held: held)
        #expect(!promotion.isPossible)
        #expect(promotion.total == 0)
        #expect(promotion.leftBehind.isEmpty)
    }

    @Test("A list the server holds all of leaves nothing behind")
    func aFullyHeldListLeavesNothingBehind() {
        let promotion = promotion(["a", "c"], held: held)
        #expect(promotion.isPossible)
        #expect(promotion.copying == ["a", "c"])
        #expect(promotion.leftBehind.isEmpty)
    }
}
