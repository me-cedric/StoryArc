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
}
