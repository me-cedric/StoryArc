import SwiftUI
import Testing

@testable import EpubReaderFeature

/// `reading-themes`, *Brightness is reader-local*.
@Suite("Brightness across the reader's lifecycle")
struct EpubReaderBrightnessTests {

    @Test("Leaving restores the captured device level, when the reader set one of their own")
    func departureRestoresWhenReaderSetOne() {
        let restored = EpubReaderBrightness.onDeparture(readerBrightness: 0.6, captured: 0.9)

        #expect(
            restored == 0.9,
            "Leaving with a reader-local brightness in force did not restore the device's own."
        )
    }

    @Test("Leaving does nothing when the reader never touched the slider")
    func departureDoesNothingWithNoReaderBrightness() {
        let restored = EpubReaderBrightness.onDeparture(readerBrightness: nil, captured: 0.9)

        #expect(
            restored == nil,
            """
            Leaving restored the captured value even though the reader set no reader-local \
            brightness. Before this, `onDisappear` always wrote the captured value back, so a \
            Control Center change made mid-session was undone the moment the reader left — \
            nothing reader-local was in force to justify undoing it.
            """
        )
    }

    @Test("A return to the foreground reapplies the reader's own brightness")
    func scenePhaseActiveReappliesReaderBrightness() {
        let toApply = EpubReaderBrightness.onScenePhaseChange(to: .active, readerBrightness: 0.4)

        #expect(
            toApply == 0.4,
            """
            A return from the background did not reapply the reader's brightness. Apple \
            documents that an app's own brightness change lasts only while it is active, so \
            without this the screen shows the device level again while the slider still \
            reports the reader's.
            """
        )
    }

    @Test("Going to the background applies nothing")
    func scenePhaseBackgroundAppliesNothing() {
        let toApply = EpubReaderBrightness.onScenePhaseChange(to: .background, readerBrightness: 0.4)

        #expect(toApply == nil, "Backgrounding wrote a brightness change that reads nowhere.")
    }

    @Test("A return to the foreground with no reader brightness applies nothing")
    func scenePhaseActiveWithNoReaderBrightnessAppliesNothing() {
        let toApply = EpubReaderBrightness.onScenePhaseChange(to: .active, readerBrightness: nil)

        #expect(
            toApply == nil,
            "A reader who never touched the slider has nothing to reassert on return."
        )
    }
}
