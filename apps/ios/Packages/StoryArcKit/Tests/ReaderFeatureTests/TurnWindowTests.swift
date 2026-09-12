import Testing

internal import StoryArcCore

@testable import ReaderFeature

/// Which transition modes a change of displayed index counts frames for.
///
/// `page-transitions`'s *Frame budget* covers "any transition", and for months the
/// instrument reached the curl alone. This is the rule that says which of the others it
/// reaches, held outside the views so that a test can call it.
///
/// **No case below asserts a frame rate.** A Mac draws at its own, and the rate is read from
/// the display at run time and reported, never asserted. See `FrameRunTests`.
///
/// Android's `TurnWindowTest` asserts the same table, case for case.
@Suite("Turn window")
@MainActor
struct TurnWindowTests {

    @Test("Exactly the two containers that animate a turn and report no end open a run")
    func coversSlideAndFade() {
        let timed = PageTransition.allCases.filter { $0.turnWindow != nil }
        #expect(timed == [.slide, .fastFade])
    }

    @Test("The curl counts its own frames, so its index opens nothing")
    func curlIsBoundedByTheFinger() {
        #expect(PageTransition.pageCurl.turnWindow == nil)
    }

    @Test("A scroll has no discrete turn, so its index opens nothing")
    func scrollOpensNoRun() {
        for mode in PageTransition.allCases where mode.isScroll {
            #expect(mode.turnWindow == nil)
        }
    }

    /// A window shorter than the animation it covers stops counting before the turn ends,
    /// which is where a late frame is most likely. The cross-dissolve is the one animation
    /// length this package states, so it is the floor every window has to clear.
    @Test("A window outlasts the animation it has to cover")
    func windowOutlastsTheFade() {
        for window in PageTransition.allCases.compactMap(\.turnWindow) {
            #expect(window > ReaderView.fadeDuration)
        }
    }
}
