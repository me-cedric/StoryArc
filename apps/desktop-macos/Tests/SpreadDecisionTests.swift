import CoreGraphics
import StoryArcCore
import Testing

@testable import StoryArc

/// The pairing rule of task 2.14 across odd and even counts and right-to-left.
@Suite("Spread decision")
struct SpreadDecisionTests {
    @Test("A wide window pairs, a narrow one shows one page")
    func windowShape() {
        #expect(SpreadDecision.pairs(viewport: CGSize(width: 1400, height: 800)))
        #expect(!SpreadDecision.pairs(viewport: CGSize(width: 700, height: 900)))
        #expect(!SpreadDecision.pairs(viewport: CGSize(width: 800, height: 0)))
    }

    @Test("The cover is alone, then pairs, and the last page of an odd count is alone")
    func oddCount() {
        let layout = SpreadDecision.layout(pageCount: 7, wide: [], pairs: true)
        #expect(layout.slots.map(\.pages) == [[0], [1, 2], [3, 4], [5, 6]])

        let even = SpreadDecision.layout(pageCount: 8, wide: [], pairs: true)
        #expect(even.slots.map(\.pages) == [[0], [1, 2], [3, 4], [5, 6], [7]])
        #expect(even.slots.last?.isPair == false)
    }

    @Test("A page that is already a spread shows alone and full width")
    func widePageAlone() {
        let layout = SpreadDecision.layout(pageCount: 6, wide: [3], pairs: true)
        #expect(layout.slots.map(\.pages) == [[0], [1, 2], [3], [4, 5]])
    }

    @Test("A narrow window keeps the reader on the same page, one per slot")
    func narrowWindow() {
        let layout = SpreadDecision.layout(pageCount: 5, wide: [], pairs: false)
        #expect(layout.slots.map(\.pages) == [[0], [1], [2], [3], [4]])
        #expect(layout.slot(containing: 3) == 3)
        #expect(SpreadDecision.layout(pageCount: 5, wide: [], pairs: true).slot(containing: 3) == 2)
    }

    @Test("Right-to-left puts the page read first on the right")
    func rightToLeftOrder() {
        let pair = Spread(leading: 4, trailing: 5)
        #expect(SpreadDecision.screenOrder(pair, isRightToLeft: false) == [4, 5])
        #expect(SpreadDecision.screenOrder(pair, isRightToLeft: true) == [5, 4])
        #expect(SpreadDecision.screenOrder(Spread(leading: 9), isRightToLeft: true) == [9])
    }

    @Test("The cover pairs with page two when the reader turns cover-alone off")
    func coverPaired() {
        let layout = SpreadDecision.layout(pageCount: 4, wide: [], pairs: true, coverAlone: false)
        #expect(layout.slots.map(\.pages) == [[0, 1], [2, 3]])
    }
}
