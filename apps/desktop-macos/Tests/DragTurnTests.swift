import Testing

@testable import StoryArc

/// The drag threshold of task 2.15.
@Suite("Drag to turn")
struct DragTurnTests {
    @Test("Past the threshold the page turns the way the drag went")
    func pastThreshold() {
        #expect(DragTurn.step(translation: -200, width: 900, isRightToLeft: false) == 1)
        #expect(DragTurn.step(translation: 200, width: 900, isRightToLeft: false) == -1)
    }

    @Test("Short of the threshold no turn is counted")
    func shortOfThreshold() {
        #expect(DragTurn.step(translation: -100, width: 900, isRightToLeft: false) == 0)
        #expect(DragTurn.step(translation: 30, width: 200, isRightToLeft: false) == 0)
        #expect(DragTurn.step(translation: 0, width: 900, isRightToLeft: true) == 0)
    }

    @Test("Mirrored in a right-to-left publication")
    func mirrored() {
        #expect(DragTurn.step(translation: -200, width: 900, isRightToLeft: true) == -1)
        #expect(DragTurn.step(translation: 200, width: 900, isRightToLeft: true) == 1)
    }

    @Test("The threshold is 48 points on a narrow page and a sixth of a wide one")
    func threshold() {
        #expect(DragTurn.threshold(width: 200) == 48)
        #expect(DragTurn.threshold(width: 1200) == 200)
        #expect(DragTurn.progress(translation: -300, width: 1200) == 0.25)
        #expect(DragTurn.progress(translation: 5000, width: 1200) == 1)
    }
}
