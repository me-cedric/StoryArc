import Testing

@testable import ReaderFeature

/// The arithmetic behind a page turn, and the one part of it a screenshot cannot show.
///
/// `comic-reader` requires a curl still settling to be catchable: "the new gesture takes
/// over from the current position without the page snapping". That is a statement about
/// where a drag *starts counting from*, so it is a statement about arithmetic — and the
/// defect it forbids was arithmetic, a settle caught at 0.8 recomputed from zero.
///
/// Android's `CurlTurnTest` asserts the same table, case for case.
@Suite("Curl turn")
struct CurlTurnTests {

    private let width: Double = 1000

    // MARK: - Following the finger

    @Test("A drag from a flat page turns it as far as the finger went")
    func dragFromFlat() {
        let reached = CurlTurn.progress(base: 0, travel: -300, width: width, isRightToLeft: false)
        #expect(abs(reached - 0.3) < 0.001)
    }

    @Test("Turn-space carries the mirroring, so a flick can be told forwards from back")
    func turnSpace() {
        #expect(CurlTurn.forward(travel: -12, isRightToLeft: false) == 12)
        #expect(CurlTurn.forward(travel: 12, isRightToLeft: false) == -12)
        #expect(CurlTurn.forward(travel: 12, isRightToLeft: true) == 12)
    }

    @Test("A right-to-left publication turns forward on the other direction")
    func rightToLeft() {
        #expect(CurlTurn.progress(base: 0, travel: 300, width: width, isRightToLeft: true) == 0.3)
        #expect(CurlTurn.progress(base: 0, travel: -300, width: width, isRightToLeft: true) == 0)
    }

    // MARK: - Interruption

    @Test("A drag caught mid-settle carries the page's progress as its base")
    func caughtSettleKeepsItsPlace() {
        // The scenario itself: the settle stands at 0.8 and the finger has barely moved.
        // Recomputed from zero this is 0.001, which is the snap the scenario forbids.
        let reached = CurlTurn.progress(base: 0.8, travel: -1, width: width, isRightToLeft: false)
        #expect(abs(reached - 0.8) < 0.01)
    }

    @Test("A drag from a caught settle is an offset from where the page stands")
    func caughtSettleIsAnOffset() {
        let reached = CurlTurn.progress(base: 0.8, travel: -100, width: width, isRightToLeft: false)
        #expect(abs(reached - 0.9) < 0.001)
    }

    @Test("Dragging back from a caught settle unwinds the page rather than pinning it")
    func caughtSettleUnwinds() {
        // Clamped at zero when the drag was absolute, so the page could never be pushed
        // back: every backwards move read as "no progress" instead of "less progress".
        let reached = CurlTurn.progress(base: 0.8, travel: 300, width: width, isRightToLeft: false)
        #expect(abs(reached - 0.5) < 0.001)
    }

    @Test("A caught settle cannot be dragged past either end")
    func caughtSettleStaysInRange() {
        #expect(CurlTurn.progress(base: 0.8, travel: -900, width: width, isRightToLeft: false) == 1)
        #expect(CurlTurn.progress(base: 0.8, travel: 900, width: width, isRightToLeft: false) == 0)
    }

    @Test("A width nothing has measured yet leaves the page where it stands")
    func unmeasuredWidth() {
        #expect(CurlTurn.progress(base: 0.8, travel: -300, width: 0, isRightToLeft: false) == 0.8)
    }

    // MARK: - The release

    @Test("Past halfway the turn completes")
    func halfway() {
        #expect(CurlTurn.settles(progress: 0.51, isFlick: false))
        #expect(!CurlTurn.settles(progress: 0.5, isFlick: false))
    }

    @Test("A flick completes whatever the distance")
    func flickCompletes() {
        #expect(CurlTurn.settles(progress: 0.06, isFlick: true))
        #expect(!CurlTurn.settles(progress: 0.06, isFlick: false))
    }

    @Test("A flick from a page that never left flat does not turn it")
    func flickFromFlat() {
        #expect(!CurlTurn.settles(progress: 0.05, isFlick: true))
    }

    @Test("A settle caught and released where it stood still completes")
    func caughtSettleReleased() {
        // The other half of interruption: a turn caught at 0.8 and let go is past
        // halfway, so it finishes rather than springing back to a page already gone.
        #expect(CurlTurn.settles(progress: 0.8, isFlick: false))
    }
}
