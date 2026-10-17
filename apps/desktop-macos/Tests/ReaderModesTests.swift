import CoreGraphics
import Foundation
import Persistence
import ReaderFeature
import StoryArcCore
import Testing

@testable import StoryArc

/// `page-transitions`, *Transition modes*, and `comic-reader`, *Page transitions in the
/// comic reader*, *Fit modes* and *Zoom persists across pages*, on the Mac.
@Suite("Reader modes")
struct ReaderModesTests {
    // MARK: - How a turn is drawn

    @Test("Slide brings the next page in from the side reading moves towards, mirrored right to left")
    func slideDirection() {
        #expect(PageChanges.change(effective: .slide, step: 1, isRightToLeft: false) == .slide(fromTrailing: true))
        #expect(PageChanges.change(effective: .slide, step: -1, isRightToLeft: false) == .slide(fromTrailing: false))
        #expect(PageChanges.change(effective: .slide, step: 1, isRightToLeft: true) == .slide(fromTrailing: false))
        #expect(PageChanges.change(effective: .fastFade, step: 1, isRightToLeft: false) == .fade)
        #expect(PageChanges.change(effective: .verticalScroll, step: 1, isRightToLeft: false) == .cut)
        #expect(PageChanges.change(effective: .slide, step: 0, isRightToLeft: false) == .cut)
    }

    // MARK: - The picker

    @Test("Every mode is listed; the curl is absent with one sentence, since the Mac has none yet")
    func rowsWithoutCurl() {
        let choices = TransitionChoices(chosen: .slide, axis: .horizontal, reduceMotion: false, canCurl: false)
        let rows = TransitionMenu.rows(choices)
        #expect(rows.map(\.mode) == [.slide, .fastFade, .horizontalScroll, .verticalScroll])
        #expect(rows.allSatisfy { $0.reasonKey == nil })
        #expect(rows.first { $0.isChosen }?.mode == .slide)
        #expect(TransitionMenu.absentCurlKey(choices) == "desktop.transition.curlLater")
    }

    @Test("Under Reduce Motion the slide is listed, marked unavailable with the reason, and the fade runs")
    func reduceMotion() {
        let choices = TransitionChoices(chosen: .slide, axis: .vertical, reduceMotion: true, canCurl: false)
        let slide = TransitionMenu.rows(choices).first { $0.mode == .slide }
        #expect(slide?.reasonKey == "desktop.transition.reason.reduceMotion")
        #expect(slide?.isChosen == true, "the stored choice was lost")
        #expect(choices.effective == .fastFade)
        #expect(TransitionMenu.rows(choices).first?.mode == .slide)
    }

    // MARK: - Remembered per series, with a default

    @Test("A mode chosen for one issue applies to its series; a series never opened takes the default")
    @MainActor
    func persistence() throws {
        let scratch = try ScratchDefaults(prefix: "mac-modes-")
        defer { scratch.remove() }
        let preferences = ReaderPreferences(defaults: scratch.defaults)
        let issue1 = TestPublications.make(1, series: "Saga")
        let issue2 = TestPublications.make(2, series: "Saga")
        let other = TestPublications.make(3, series: "Monstress")
        let file = URL(filePath: "/tmp/none.cbz")

        func mode(_ publication: Publication) -> PageTransition {
            ReaderModel(publication: publication, url: file, preferences: preferences).settings.transition
        }
        ReaderModel(publication: issue1, url: file, preferences: preferences, canCurl: false).choose(.fastFade)
        #expect(mode(issue2) == .fastFade)
        #expect(mode(other) == .slide)

        MacReadingDefaults.setTransition(.verticalScroll, in: preferences)
        #expect(mode(other) == .verticalScroll)
        #expect(mode(issue2) == .fastFade)
        #expect(preferences.themes().default(for: .reflowable).transition == .slide, "the comic default leaked")
        #expect(MacReadingDefaults.transition(in: preferences) == .verticalScroll)
    }

    // MARK: - Fit modes

    @Test("Each fit sizes the page as a multiple of fit-to-screen and opens at its top on the reading side")
    func fits() {
        let viewport = CGSize(width: 1000, height: 800)
        let fitted = CGSize(width: 400, height: 800)
        func fit(_ mode: PageFit, rightToLeft: Bool = false) -> ZoomModel {
            ZoomModel().fitting(
                mode, fittedSize: fitted, viewport: viewport, pixelWidth: 1200, isRightToLeft: rightToLeft
            )
        }
        let width = fit(.width)
        #expect(width.scale == 2.5)
        #expect(width.offset.height == (800 * 2.5 - 800) / 2, "fit width opened mid-page")
        #expect(fit(.screen) == ZoomModel())
        #expect(fit(.height).scale == 1)
        let original = fit(.original, rightToLeft: true)
        #expect(original.scale == 3)
        #expect(original.offset.width < 0, "right to left opened on the left")
    }

    @Test("The fit for a page is never past the zoom ceiling")
    func fitCeiling() {
        let tiny = ZoomModel().fitting(
            .original, fittedSize: CGSize(width: 10, height: 20), viewport: CGSize(width: 100, height: 20),
            pixelWidth: 1000, isRightToLeft: false
        )
        #expect(tiny.scale == ZoomModel.ceiling)
    }
}
