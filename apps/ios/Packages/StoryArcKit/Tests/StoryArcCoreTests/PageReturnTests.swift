import Testing

@testable import StoryArcCore

/// The way back from a slider jump.
///
/// `comic-reader`: "releasing jumps there, with a control to return to the previous
/// position". Android's `PageReturnTest` asserts the same cases.
@Suite("Page return")
struct PageReturnTests {
    @Test("A jump marks where it came from")
    func jumpLeavesAMark() {
        #expect(PageReturn().jumped(from: 4, to: 180).mark == 4)
    }

    @Test("A jump that goes nowhere leaves no mark")
    func standingStill() {
        #expect(PageReturn().jumped(from: 4, to: 4).mark == nil)
    }

    @Test("A step of one page is a turn, and a turn is undone by turning back")
    func oneStepIsATurn() {
        #expect(PageReturn().jumped(from: 4, to: 5).mark == nil)
        #expect(PageReturn().jumped(from: 4, to: 3).mark == nil)
    }

    @Test("A second jump offers the place the second one started, not the first")
    func latestJumpWins() {
        let marked = PageReturn()
            .jumped(from: 4, to: 180)
            .jumped(from: 180, to: 60)
        #expect(marked.mark == 180)
    }

    @Test("Reading back to the mark retires the offer")
    func readingBackClearsIt() {
        var marked = PageReturn().jumped(from: 4, to: 180)
        marked = marked.moved(to: 179)
        #expect(marked.mark == 4)
        marked = marked.moved(to: 4)
        #expect(marked.mark == nil)
    }

    @Test("Taking the mark stops it being offered twice")
    func takingClearsIt() {
        #expect(PageReturn().jumped(from: 4, to: 180).taken().mark == nil)
    }

    @Test("A jump backwards is a jump too — the page slider runs both ways")
    func jumpingBackwards() {
        #expect(PageReturn().jumped(from: 180, to: 4).mark == 180)
    }
}
