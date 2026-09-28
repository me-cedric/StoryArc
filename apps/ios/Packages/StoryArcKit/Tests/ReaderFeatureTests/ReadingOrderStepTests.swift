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
}
