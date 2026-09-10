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
        #expect(CurlTurn.progress(base: 0.8, travel: 1900, width: width, isRightToLeft: false) == -1)
    }

    // MARK: - The other direction

    @Test("A drag backwards from flat turns the page behind, which is a negative progress")
    func dragBackFromFlat() {
        // The reader's report: "page curl only seems to work in one direction, sliding to
        // the previous page does nothing". It did nothing because the range was clamped at
        // zero, so a backwards drag from a flat page was arithmetically indistinguishable
        // from no drag at all.
        let reached = CurlTurn.progress(base: 0, travel: 300, width: width, isRightToLeft: false)
        #expect(abs(reached + 0.3) < 0.001)
    }

    @Test("The range clamps at a whole turn in each direction")
    func rangeClamps() {
        #expect(CurlTurn.progress(base: 0, travel: -4000, width: width, isRightToLeft: false) == 1)
        #expect(CurlTurn.progress(base: 0, travel: 4000, width: width, isRightToLeft: false) == -1)
    }

    @Test("A right-to-left publication mirrors both signs")
    func rightToLeftMirrorsBoth() {
        #expect(CurlTurn.progress(base: 0, travel: 300, width: width, isRightToLeft: true) == 0.3)
        #expect(CurlTurn.progress(base: 0, travel: -300, width: width, isRightToLeft: true) == -0.3)
    }

    @Test("With no page behind it the negative range collapses to nothing")
    func firstPageCannotTurnBack() {
        // `page-transitions`: a backwards drag on the first page "moves nothing". The guard
        // is here rather than in the shader, which would have no sheet to turn and would
        // draw the page beneath at rest.
        #expect(
            CurlTurn.progress(
                base: 0, travel: 300, width: width, isRightToLeft: false, canTurnBack: false
            ) == 0
        )
        #expect(
            CurlTurn.progress(
                base: 0.4, travel: 400, width: width, isRightToLeft: false, canTurnBack: false
            ) == 0
        )
    }

    @Test("With no page beneath the forward range is left alone, because the end screen is a turn")
    func lastPageStillTurns() {
        // `comic-reader` reaches an end screen by turning past the last page, so the last
        // page's forward turn is a turn and not a nothing. Stated as a test because the
        // symmetry is tempting and would take the end screen away.
        #expect(CurlTurn.progress(base: 0, travel: -1200, width: width, isRightToLeft: false) == 1)
    }

    @Test("A backwards flick completes a backwards turn")
    func backwardsFlick() {
        #expect(CurlTurn.flicks(velocity: -60, progress: -0.1))
        #expect(CurlTurn.settles(progress: -0.06, isFlick: true))
    }

    @Test("A flick has to agree with where the page is already going")
    func flickAgrees() {
        // A fast finger dragging the page back at a forward progress has said it does not
        // want the turn. An unsigned flick completed it anyway.
        #expect(!CurlTurn.flicks(velocity: -60, progress: 0.3))
        #expect(!CurlTurn.flicks(velocity: 60, progress: -0.3))
        #expect(CurlTurn.flicks(velocity: 60, progress: 0.3))
    }

    @Test("Past halfway backwards the turn completes too")
    func halfwayBack() {
        #expect(CurlTurn.settles(progress: -0.51, isFlick: false))
        #expect(!CurlTurn.settles(progress: -0.5, isFlick: false))
    }

    @Test("A negative progress turns the page behind over the page in view")
    func sheetsBackwards() {
        // The mapping the shader is given: a backwards turn is the forward projection run
        // on the previous page, at one minus the distance dragged. At a whole turn back the
        // previous page is flat and fully in view; at nothing dragged it is folded away and
        // the current page is what shows.
        let sheets = CurlTurn.sheets(
            progress: -0.9, page: "current", beneath: "next", previous: "previous"
        )

        #expect(sheets.turning == "previous")
        #expect(sheets.under == "current")
        #expect(abs(sheets.progress - 0.1) < 0.001)
    }

    @Test("A positive progress turns the page in view over the one beneath it")
    func sheetsForwards() {
        let sheets = CurlTurn.sheets(
            progress: 0.3, page: "current", beneath: "next", previous: "previous"
        )

        #expect(sheets.turning == "current")
        #expect(sheets.under == "next")
        #expect(abs(sheets.progress - 0.3) < 0.001)
    }

    @Test("A flat page is the page in view, whichever way the last drag went")
    func sheetsFlat() {
        let sheets = CurlTurn.sheets(
            progress: 0, page: "current", beneath: "next", previous: "previous"
        )

        #expect(sheets.turning == "current")
        #expect(sheets.progress == 0)
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
