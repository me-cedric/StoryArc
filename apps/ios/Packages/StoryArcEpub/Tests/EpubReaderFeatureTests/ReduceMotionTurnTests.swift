import Foundation
import Testing

import StoryArcCore
@testable import EpubReaderFeature

/// `page-transitions`, *Reduce Motion is on*: "Curl and Slide are replaced by Fast fade".
///
/// The reflowable reader read the chosen mode, so a chosen Slide stayed Readium's own
/// animated slide with Reduce Motion on. Android asserts the same rule in
/// `ReduceMotionTurnTest`.
@MainActor
@Suite("The reflowable reader's turn under Reduce Motion")
struct ReduceMotionTurnTests {

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

    @Test("A chosen Slide becomes Fast fade's own turn while Reduce Motion is on")
    func slideBecomesFastFade() {
        let reader = model(choosing: .slide)
        #expect(!reader.ownsTheTurn)

        reader.reduceMotion = true
        #expect(reader.ownsTheTurn)

        // `Reduce Motion turned off mid-session`: the chosen mode comes straight back.
        reader.reduceMotion = false
        #expect(!reader.ownsTheTurn)
    }

    @Test("Scroll is not a slide, so Readium keeps it under Reduce Motion")
    func scrollStaysWithReadium() {
        let reader = model(choosing: .verticalScroll)
        reader.reduceMotion = true
        #expect(!reader.ownsTheTurn)
    }
}
