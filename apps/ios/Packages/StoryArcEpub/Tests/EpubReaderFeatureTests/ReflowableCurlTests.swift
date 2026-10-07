import CoreGraphics
import Foundation
import Testing

import StoryArcCore
@testable import EpubReaderFeature

/// That a page of prose can curl, which is task 8.12 and closes
/// `reader-theming-and-page-transitions` 4.3b.
///
/// Three things have to hold together, and each is asserted on its own below: the mode is
/// offered over reflowable content at all, the reflowable reader claims the turn when it is
/// chosen, and the turn it claims is the curl rather than the fade.
///
/// **What is not here is the roll.** It is a Metal shader filling a rectangle over a
/// `UIHostingController`, and no test process on this machine has a GPU in it —
/// `PageCurlShaderTests` is the tripwire on the shader's text and
/// `docs/designs/screenshots/` holds the frame. Android asserts the same three rules in
/// `ReflowableCurlTest`.
@MainActor
@Suite("The curl over reflowable text")
struct ReflowableCurlTests {

    private func model(choosing transition: PageTransition) -> EpubReaderModel {
        let url = URL(fileURLWithPath: "/nowhere.epub")
        let model = EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "Nowhere",
                origin: .embedded
            ),
            url: url
        )
        model.transition = transition
        return model
    }

    @Test("A reflowable book offers the curl, and does not name it unavailable")
    func theCurlIsOffered() {
        let choices = model(choosing: .pageCurl).transitions(reduceMotion: false)

        #expect(choices.offered.contains(.pageCurl))
        #expect(choices.unavailable[.pageCurl] == nil)
    }

    @Test("Curl is a turn this reader draws, not one Readium draws")
    func theReaderClaimsTheTurn() {
        // The whole of why: Readium's paginated scroll animates a Slide, so it has to stop
        // for a transition StoryArc draws. `ownsTheTurn` is what stops it.
        #expect(model(choosing: .pageCurl).ownsTheTurn)
    }

    @Test("The turn Curl claims is the roll, and the turn Fast fade claims is the dip")
    func eachModeClaimsItsOwnTurn() {
        // One funnel, `turn(forward:)`, reads this. A mode that answered `.fastFade` here
        // would dip through the page colour under a reader who chose the curl.
        #expect(model(choosing: .pageCurl).drawnTurn == .pageCurl)
        #expect(model(choosing: .fastFade).drawnTurn == .fastFade)
        #expect(model(choosing: .slide).drawnTurn == nil)
        #expect(model(choosing: .verticalScroll).drawnTurn == nil)
    }

    @Test("Reduce Motion still replaces the curl with the fade")
    func reduceMotionStillWins() {
        // `page-transitions`: "Curl and Slide are replaced by Fast fade". Offering the curl
        // over text must not reach around that substitution.
        let reader = model(choosing: .pageCurl)
        reader.reduceMotion = true

        #expect(reader.drawnTurn == .fastFade)
    }

    @Test("The curl works in the scale its pages were rastered at, not the device's")
    @MainActor
    func theCurlUsesItsRastersScale() throws {
        // A 600 by 900 pixel raster taken at 2x is a 300 by 450 point page. Read at the
        // device's scale — 3x on the simulator this runs on — the shader drew it at 200 by
        // 300, which is what an iPad window on an external display got.
        let context = try #require(CGContext(
            data: nil, width: 600, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let page = try #require(context.makeImage())

        let curl = ReflowableCurl(
            page: page, other: page, isRightToLeft: false, progress: 0, scale: 2
        )

        #expect(curl.size == CGSize(width: 300, height: 450))
    }
}
