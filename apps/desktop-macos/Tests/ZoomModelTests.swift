import CoreGraphics
import Testing

@testable import StoryArc

/// The zoom model of task 2.13, with the iOS limits.
@Suite("Zoom model")
struct ZoomModelTests {
    private let fitted = CGSize(width: 400, height: 600)
    private let viewport = CGSize(width: 800, height: 600)

    @Test("Keys step in and out and never pass the limits, silently")
    func keysAndLimits() {
        var zoom = ZoomModel()
        for _ in 0..<40 { zoom = zoom.zoomedIn() }
        #expect(zoom.scale == ZoomModel.ceiling)
        #expect(zoom.zoomedIn() == zoom)

        for _ in 0..<40 { zoom = zoom.zoomedOut() }
        #expect(zoom.scale == 1)
        #expect(!zoom.isZoomed)
        #expect(zoom.zoomedOut() == zoom)
    }

    @Test("A double click gives the phone's level from fit, and fits again from anywhere else")
    func doubleClick() {
        let once = ZoomModel().doubleClicked()
        #expect(once.scale == ZoomModel.doubleClickFactor)
        #expect(once.doubleClicked().scale == 1)
        #expect(ZoomModel().zoomedIn().doubleClicked().scale == 1)
    }

    @Test("Pinch and the wheel multiply the scale inside the limits")
    func pinchAndWheel() {
        #expect(ZoomModel().magnified(by: 2).scale == 2)
        #expect(ZoomModel().magnified(by: 100).scale == ZoomModel.ceiling)
        #expect(ZoomModel().magnified(by: 0.2).scale == 1)
        let wheeled = ZoomModel().wheeled(by: 3)
        #expect(abs(wheeled.scale - pow(ZoomModel.wheelStep, 3)) < 0.0001)
        #expect(ZoomModel().wheeled(by: -3).scale == 1)
    }

    @Test("A fitted page cannot pan; a zoomed one pans to its edges and no further")
    func panning() {
        let delta = CGSize(width: 500, height: 500)
        #expect(ZoomModel().panned(by: delta, fittedSize: fitted, viewport: viewport).offset == .zero)

        let zoomed = ZoomModel().magnified(by: 3)
        let panned = zoomed.panned(by: delta, fittedSize: fitted, viewport: viewport)
        // 400 × 3 = 1200 wide against 800: 200 of slack each side. 600 × 3 against 600: 600.
        #expect(panned.offset == CGSize(width: 200, height: 500))
        let again = panned.panned(by: delta, fittedSize: fitted, viewport: viewport)
        #expect(again.offset == CGSize(width: 200, height: 600))
    }

    @Test("A turn keeps the zoom and opens the page at its top, on the side reading starts from")
    func turnKeepsZoom() {
        let fitted = CGSize(width: 400, height: 600)
        let viewport = CGSize(width: 400, height: 600)
        let zoomed = ZoomModel().magnified(by: 2)
            .panned(by: CGSize(width: -50, height: -300), fittedSize: fitted, viewport: viewport)

        let next = zoomed.turned(isRightToLeft: false, fittedSize: fitted, viewport: viewport)
        #expect(next.scale == 2)
        #expect(next.offset == CGSize(width: 200, height: 300))

        let manga = zoomed.turned(isRightToLeft: true, fittedSize: fitted, viewport: viewport)
        #expect(manga.offset == CGSize(width: -200, height: 300))

        #expect(ZoomModel().turned(isRightToLeft: false, fittedSize: fitted, viewport: viewport) == ZoomModel())
    }

    @Test("Fit clears the pan, and a resize settles the pan inside the new edges")
    func fitAndSettle() {
        let zoomed = ZoomModel().magnified(by: 3)
            .panned(by: CGSize(width: 150, height: 0), fittedSize: fitted, viewport: viewport)
        #expect(zoomed.fitted() == ZoomModel())
        let wider = CGSize(width: 1400, height: 600)
        #expect(zoomed.settled(fittedSize: fitted, viewport: wider).offset == .zero)
    }
}
