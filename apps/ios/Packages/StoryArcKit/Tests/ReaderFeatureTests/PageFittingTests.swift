import CoreGraphics
import Testing

import StoryArcCore
@testable import ReaderFeature

/// When a page counts as fitted, and what the fit is a multiple of.
///
/// Both halves are pure, so they are tested here rather than against a simulator. The
/// first half is a regression: a page opened on a cold launch was fitted against a
/// scroll view UIKit had not laid out yet, the fit was recorded anyway, and the page
/// sat at its own pixel size in the corner until something else changed the key.
@Suite("Page fitting")
struct PageFittingTests {

    private let viewport = CGSize(width: 400, height: 800)

    @Test("a fit asked for before there is a view to apply it to is not recorded")
    func unlaidOutViewDoesNotCount() {
        var applied = AppliedFit()
        let key = AppliedFit.key(pageID: "1", fit: .screen, viewport: viewport)

        // What a cold launch does: SwiftUI has a size, UIKit has not laid out yet.
        #expect(applied.claim(key, layout: .zero) == false)

        // So the same fit is still owed, and the layout that follows applies it.
        #expect(applied.claim(key, layout: viewport) == true)
    }

    @Test("a fit that was applied is not applied a second time")
    func appliedOnlyOnce() {
        var applied = AppliedFit()
        let key = AppliedFit.key(pageID: "1", fit: .width, viewport: viewport)

        #expect(applied.claim(key, layout: viewport) == true)
        // Every redraw asks again. Saying yes here would undo the reader's own pinch.
        #expect(applied.claim(key, layout: viewport) == false)
    }

    @Test("a new page, a new mode or a new size is a new fit")
    func keyDistinguishesWhatMatters() {
        var applied = AppliedFit()
        let turned = CGSize(width: 800, height: 400)

        let first = applied.claim(AppliedFit.key(pageID: "1", fit: .screen, viewport: viewport), layout: viewport)
        let nextPage = applied.claim(AppliedFit.key(pageID: "2", fit: .screen, viewport: viewport), layout: viewport)
        let nextMode = applied.claim(AppliedFit.key(pageID: "2", fit: .width, viewport: viewport), layout: viewport)
        let rotated = applied.claim(AppliedFit.key(pageID: "2", fit: .width, viewport: turned), layout: turned)

        #expect(first == true)
        #expect(nextPage == true)
        #expect(nextMode == true)
        #expect(rotated == true)
    }

    @Test("a hairline change of viewport is the same fit")
    func hairlineIsNotANewFit() {
        // A rotation reports fractional sizes on the way through. Treating each as a new
        // fit would re-apply one over a pinch the reader had just made.
        let narrower = AppliedFit.key(pageID: "1", fit: .screen, viewport: CGSize(width: 400.2, height: 800))
        let wider = AppliedFit.key(pageID: "1", fit: .screen, viewport: CGSize(width: 400.8, height: 800))
        #expect(narrower == wider)
    }

    @Test("a page is fitted by whichever axis runs out first")
    func fittedSizeUsesTheLimitingAxis() {
        // The same shape as the viewport: both axes run out together, so it fills it.
        #expect(fitted(CGSize(width: 1000, height: 2000), in: viewport) == viewport)

        // Taller than the viewport's shape, so height limits it and the artwork ends up
        // narrower than the screen — the letterboxing the panning bounds care about.
        #expect(fitted(CGSize(width: 500, height: 2000), in: viewport) == CGSize(width: 200, height: 800))
    }

    @Test("a page with no size fits to nothing rather than to a division by zero")
    func degenerateImageIsRefused() {
        #expect(fitted(.zero, in: viewport) == .zero)
    }

    @Test("fit-to-width magnifies a letterboxed page until it spans the viewport")
    func fitToWidthSpansTheViewport() {
        let owed = OwedFit(
            pageID: "1",
            mode: .width,
            imageSize: CGSize(width: 500, height: 2000),
            viewport: viewport
        )
        #expect(owed.scale(upTo: 6) == 2)
        #expect(owed.opensAtTheTop == true)
    }

    @Test("a fit never opens the page past what the view will hold")
    func scaleIsCapped() {
        // A wide scan at original size wants 250x, which is not a page anybody can read.
        let owed = OwedFit(
            pageID: "1",
            mode: .original,
            imageSize: CGSize(width: 100_000, height: 2000),
            viewport: viewport
        )
        #expect(owed.scale(upTo: 6) == 6)
    }

    @Test("fit-to-screen opens the whole page, from its middle")
    func fitToScreenIsUnmagnified() {
        let owed = OwedFit(
            pageID: "1",
            mode: .screen,
            imageSize: CGSize(width: 500, height: 2000),
            viewport: viewport
        )
        #expect(owed.scale(upTo: 6) == 1)
        #expect(owed.opensAtTheTop == false)
    }

    // D6: "zoom level" means the pinched scale, and fit-to-width carries it to the
    // next page rather than resetting on every turn. Android's `PageZoomTest`'s
    // fit-to-width cases assert the same table.

    @Test("fit-to-width carries a pinch, as a multiple of the next page's own fit")
    func fitToWidthCarriesAPinchForward() {
        #expect(openingScale(fitScale: 2, carried: 1.5, mode: .width) == 3)
    }

    @Test("every other mode still resets, even with a carried pinch in hand")
    func everyOtherModeIgnoresTheCarriedScale() {
        #expect(openingScale(fitScale: 1, carried: 4, mode: .screen) == 1)
        #expect(openingScale(fitScale: 2, carried: 4, mode: .original) == 2)
    }

    @Test("nothing carried is the ordinary fit")
    func nothingCarriedIsTheOrdinaryFit() {
        #expect(openingScale(fitScale: 2, carried: nil, mode: .width) == 2)
    }

    @Test("a page left at its fit carries nothing into a page of another shape")
    func aPageAtItsFitCarriesNothing() {
        // A raw scale carried page A's fit-to-width (2) into page B, whose own fit is
        // 1.5, and opened B magnified although nobody pinched. A multiple of 1 is no
        // pinch at all, whatever the next page's shape.
        #expect(openingScale(fitScale: 1.5, carried: 1, mode: .width) == 1.5)
        #expect(openingScale(fitScale: 1.5, carried: 1.005, mode: .width) == 1.5)
        #expect(openingScale(fitScale: 1.5, carried: 0.8, mode: .width) == 1.5)
    }

    @Test("an OwedFit given a carried pinch opens the page past its own fit by that much")
    func owedFitTakesACarriedScale() {
        let owed = OwedFit(
            pageID: "1",
            mode: .width,
            imageSize: CGSize(width: 500, height: 2000),
            viewport: viewport,
            carried: 2
        )
        #expect(owed.fitScale(upTo: 6) > 1)
        #expect(owed.scale(upTo: 6) == min(owed.fitScale(upTo: 6) * 2, 6))
        #expect(owed.scale(upTo: 6) > owed.fitScale(upTo: 6))
    }

    @Test("a double-tap goes back to the page's own fit, not to the pinch it carried")
    func doubleTapFitIgnoresTheCarry() {
        let carried = OwedFit(
            pageID: "1", mode: .width, imageSize: CGSize(width: 500, height: 2000),
            viewport: viewport, carried: 2
        )
        let plain = OwedFit(
            pageID: "1", mode: .width, imageSize: CGSize(width: 500, height: 2000),
            viewport: viewport
        )
        #expect(carried.fitScale(upTo: 6) == plain.scale(upTo: 6))
        #expect(isZoomedPastFit(currentScale: carried.scale(upTo: 6), fitScale: carried.fitScale(upTo: 6)))
    }

    @Test("a carried scale opens top-left in left-to-right, top-right in right-to-left")
    func openingSideFollowsReadingDirection() {
        #expect(openingXOffset(contentWidth: 800, boundsWidth: 400, isRightToLeft: false) == 0)
        #expect(openingXOffset(contentWidth: 800, boundsWidth: 400, isRightToLeft: true) == 400)
    }

    @Test("fit-to-width itself has no horizontal slack to open into, either direction")
    func noSlackMeansNoOffsetEitherWay() {
        #expect(openingXOffset(contentWidth: 400, boundsWidth: 400, isRightToLeft: true) == 0)
    }
}
