import CoreGraphics
import Testing

@testable import StoryArcCore

/// The four fit modes, as a scale against fit-to-screen.
///
/// `comic-reader` names the four; the arithmetic is what decides whether choosing
/// one shows the page or throws it off the edge. Android's `PageFitTest` asserts
/// the same table.
@Suite("Page fit")
struct PageFitTests {
    /// A tall page on a phone: the fit leaves bars either side.
    private let fitted = CGSize(width: 300, height: 600)
    private let viewport = CGSize(width: 400, height: 600)

    @Test("Fit-to-screen is the scale everything else is measured against")
    func screen() {
        #expect(PageFit.screen.scale(fitted: fitted, viewport: viewport, pixelWidth: 1200) == 1)
    }

    @Test("Fit-to-width fills the width the fit left over")
    func width() {
        let scale = PageFit.width.scale(fitted: fitted, viewport: viewport, pixelWidth: 1200)
        #expect(abs(scale - 400.0 / 300.0) < 0.001)
        // And the page is then taller than the screen, which is the point: it
        // scrolls down instead of shrinking to fit.
        #expect(fitted.height * scale > viewport.height)
    }

    @Test("Fit-to-height is already the fit for a page the screen bounds vertically")
    func height() {
        #expect(PageFit.height.scale(fitted: fitted, viewport: viewport, pixelWidth: 1200) == 1)
    }

    @Test("Original size is the image's own pixels against the space it was fitted into")
    func original() {
        let scale = PageFit.original.scale(fitted: fitted, viewport: viewport, pixelWidth: 1200)
        #expect(scale == 4)
    }

    @Test("A page smaller than the screen is never shrunk below the fit")
    func smallPage() {
        // 100 pixels of scan in 300 points of space. Shown at its own pixels it
        // would be a postage stamp in the middle of a black screen.
        #expect(PageFit.original.scale(fitted: fitted, viewport: viewport, pixelWidth: 100) == 1)
    }

    @Test("A page with no size yet does not divide by zero")
    func unmeasured() {
        let scale = PageFit.width.scale(fitted: .zero, viewport: viewport, pixelWidth: 1200)
        #expect(scale == 1)
    }
}
