import Testing

@testable import ReaderFeature

/// Double-tap toggles between the chosen fit and a zoom about the tapped point.
///
/// Decision D5: "fit" means the chosen fit mode's own scale. Fit-to-width and
/// fit-to-height are each greater than 1, so comparing against a fixed minimum (fit-to-
/// screen) zoomed a page that was already at its chosen fit further in on the first
/// double-tap instead of the second. Android's `PageZoomTest` asserts the same table.
@Suite("Double-tap zoom, against the chosen fit")
struct DoubleTapZoomTests {

    @Test("At the chosen fit, a double-tap zooms in")
    func atFitZoomsIn() {
        #expect(isZoomedPastFit(currentScale: 1.4, fitScale: 1.4) == false)
    }

    @Test("Past the chosen fit — pinched or already zoomed in — a double-tap zooms back to it")
    func pastFitZoomsBack() {
        #expect(isZoomedPastFit(currentScale: 2.5, fitScale: 1.4))
    }

    @Test("Fit-to-width, whose scale is above 1, is not read as already zoomed in")
    func fitToWidthIsNotMistakenForZoomedIn() {
        // Before D5 this compared against a fixed minimum of 1, so a fit-to-width page
        // (scale > 1) read as "already zoomed" on the very first double-tap.
        #expect(isZoomedPastFit(currentScale: 1.8, fitScale: 1.8) == false)
    }

    @Test("From fit-to-screen, a double-tap zooms in by the usual factor")
    func zoomInFromFitToScreen() {
        #expect(doubleTapZoomInScale(fitScale: 1, factor: 2.5, ceiling: 6) == 2.5)
    }

    @Test("From a fit above the usual zoom, a double-tap still zooms in, not out")
    func zoomInFromAHighFit() {
        // Fit-to-width in landscape can sit at 3.25. A fixed 2.5 target zoomed out.
        #expect(doubleTapZoomInScale(fitScale: 2, factor: 2.5, ceiling: 6) == 5)
        #expect(doubleTapZoomInScale(fitScale: 3.25, factor: 2.5, ceiling: 6) == 6)
    }

    @Test("A hairline of rounding at the fit scale is not read as zoomed past it")
    func roundingAtFitIsTolerated() {
        #expect(isZoomedPastFit(currentScale: 1.8003, fitScale: 1.8) == false)
    }
}
