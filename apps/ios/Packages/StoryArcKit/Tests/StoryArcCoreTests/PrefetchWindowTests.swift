import Testing

@testable import StoryArcCore

/// How much of a publication the reader holds decoded, and what shrinks it.
///
/// `comic-reader` names a floor — "at least the next three and previous one" — and an
/// override: "prefetch depth shrinks under memory pressure rather than the app being
/// terminated". Android's `PrefetchWindowTest` asserts the same table.
@Suite("Prefetch window")
struct PrefetchWindowTests {
    @Test("With nothing wrong, the window is the one the spec asks for")
    func full() {
        #expect(PrefetchWindow.under(.normal) == PrefetchWindow(ahead: 3, behind: 1))
        #expect(PrefetchWindow.under(.normal) == .full)
    }

    @Test("Pressure narrows the window, and the more of it the narrower")
    func shrinks() {
        let warned = PrefetchWindow.under(.warning)
        let critical = PrefetchWindow.under(.critical)
        #expect(warned.ahead < PrefetchWindow.full.ahead)
        #expect(critical.ahead < warned.ahead)
        #expect(critical.behind <= warned.behind)
    }

    @Test("Under critical pressure only the page on screen is held")
    func criticalHoldsOnlyTheCurrentPage() {
        #expect(PrefetchWindow.under(.critical).pages(around: 10, of: 100) == [10])
    }

    @Test("The pressure lifting restores the full window rather than a smaller one")
    func recovers() {
        #expect(PrefetchWindow.under(.normal) == .full)
    }

    @Test("The window is clamped to the publication rather than running off either end")
    func clamped() {
        #expect(PrefetchWindow.full.pages(around: 0, of: 3) == [0, 1, 2])
        #expect(PrefetchWindow.full.pages(around: 9, of: 10) == [8, 9])
    }

    @Test("The full window holds five pages in the middle of a long comic")
    func middleOfALongComic() {
        #expect(PrefetchWindow.full.pages(around: 50, of: 200) == [49, 50, 51, 52, 53])
    }

    @Test("A window around a page that does not exist holds nothing")
    func outsideThePublication() {
        #expect(PrefetchWindow.full.pages(around: 0, of: 0).isEmpty)
    }

    // `publication-formats`: a page too large for the device is "downsampled to the
    // display's needs for viewing and re-decoded at higher resolution when the user
    // zooms". The second decode is memory, so the same window that holds the neighbours
    // is what says how much of it there is to spend.

    @Test("A held zoom re-decodes the page at the magnification asked for")
    func zoomFollowsTheScale() {
        #expect(PrefetchWindow.full.zoomedPixelSize(display: 1000, scale: 2) == 2000)
    }

    @Test("A pinch too small to see is not worth a second decode")
    func smallPinchesAreDeclined() {
        #expect(PrefetchWindow.full.zoomedPixelSize(display: 1000, scale: 1) == nil)
        #expect(PrefetchWindow.full.zoomedPixelSize(display: 1000, scale: 1.1) == nil)
    }

    @Test("The ceiling caps a deep zoom rather than decoding whatever was asked for")
    func ceilingCaps() {
        #expect(PrefetchWindow.full.zoomedPixelSize(display: 1000, scale: 6) == 3000)
    }

    @Test("Memory pressure lowers the ceiling, and critical pressure removes it")
    func pressureLowersTheCeiling() {
        let warned = PrefetchWindow.under(.warning)
        #expect(warned.zoomedPixelSize(display: 1000, scale: 6) == 2000)
        #expect(PrefetchWindow.under(.critical).zoomedPixelSize(display: 1000, scale: 6) == nil)
    }

    @Test("A page with no size decodes to no size")
    func noDisplaySize() {
        #expect(PrefetchWindow.full.zoomedPixelSize(display: 0, scale: 4) == nil)
    }
}
