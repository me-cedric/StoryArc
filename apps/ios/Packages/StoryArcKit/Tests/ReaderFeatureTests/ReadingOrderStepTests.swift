import Testing

@testable import ReaderFeature

/// Space, Page Up/Down and the volume keys turn in reading order, not display order.
///
/// `comic-reader`: these keys mean "the next page to read". In left-to-right that is the
/// same as "the next position on screen", but under right-to-left the display order is
/// reversed and the two point opposite ways, so the step must flip. Android's
/// `ReadingOrderStepTest` asserts the same table.
@Suite("Reading-order turn step")
struct ReadingOrderStepTests {

    @Test("Left-to-right keeps the step")
    func leftToRight() {
        #expect(readingOrderStep(1, isRightToLeft: false) == 1)
        #expect(readingOrderStep(-1, isRightToLeft: false) == -1)
    }

    @Test("Right-to-left flips the step, so next still reads forward")
    func rightToLeft() {
        #expect(readingOrderStep(1, isRightToLeft: true) == -1)
        #expect(readingOrderStep(-1, isRightToLeft: true) == 1)
    }

    // `adjacentDisplayIndex`: what a curl's beneath and previous sheets are computed
    // from. `page-transitions` 8.14: a right-to-left curl turned to the previous page
    // on the next-page gesture because these were read straight off the display index.

    @Test("Left-to-right steps the display index directly")
    func leftToRightAdjacency() {
        #expect(adjacentDisplayIndex(from: 1, steps: 1, slotCount: 5, isRightToLeft: false) == 2)
        #expect(adjacentDisplayIndex(from: 1, steps: -1, slotCount: 5, isRightToLeft: false) == 0)
    }

    @Test("Right-to-left steps the display index backwards for a reading-order forward step")
    func rightToLeftAdjacency() {
        // The bug this guards: handing a right-to-left curl `from + 1` as its forward
        // reveal, which is the *previous* page once the display order is reversed.
        #expect(adjacentDisplayIndex(from: 1, steps: 1, slotCount: 5, isRightToLeft: true) == 0)
        #expect(adjacentDisplayIndex(from: 1, steps: -1, slotCount: 5, isRightToLeft: true) == 2)
    }

    @Test("A step past either end of the publication is nil")
    func adjacencyAtTheEnds() {
        #expect(adjacentDisplayIndex(from: 4, steps: 1, slotCount: 5, isRightToLeft: false) == nil)
        #expect(adjacentDisplayIndex(from: 0, steps: -1, slotCount: 5, isRightToLeft: false) == nil)
        #expect(adjacentDisplayIndex(from: 0, steps: 1, slotCount: 5, isRightToLeft: true) == nil)
    }
}
