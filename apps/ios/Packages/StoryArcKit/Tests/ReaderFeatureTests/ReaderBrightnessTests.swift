import SwiftUI
import Testing

@testable import ReaderFeature

/// `reading-themes`, *Brightness is reader-local*, over the comic reader.
///
/// A mirror of `EpubReaderBrightnessTests`: the two pure functions are identical in shape,
/// because `reading-themes` asks the same four moments of both readers.
@Suite("Brightness across the comic reader's lifecycle")
struct ReaderBrightnessTests {

    @Test("Leaving restores the captured device level, when the reader set one of their own")
    func departureRestoresWhenReaderSetOne() {
        let restored = ReaderBrightness.onDeparture(readerBrightness: 0.6, captured: 0.9)

        #expect(
            restored == 0.9,
            "Leaving with a reader-local brightness in force did not restore the device's own."
        )
    }

    @Test("Leaving does nothing when the reader never touched the slider")
    func departureDoesNothingWithNoReaderBrightness() {
        let restored = ReaderBrightness.onDeparture(readerBrightness: nil, captured: 0.9)

        #expect(
            restored == nil,
            """
            Leaving restored the captured value even though the reader set no reader-local \
            brightness. A Control Center change made mid-session has nothing reader-local to \
            justify undoing it.
            """
        )
    }

    @Test("A return to the foreground reapplies the reader's own brightness")
    func scenePhaseActiveReappliesReaderBrightness() {
        let toApply = ReaderBrightness.onScenePhaseChange(to: .active, readerBrightness: 0.4)

        #expect(
            toApply == 0.4,
            """
            A return from the background did not reapply the reader's brightness. iOS reverts \
            an app's own brightness change while it is backgrounded, so without this the \
            screen shows the device level again while the slider still reports the reader's.
            """
        )
    }

    @Test("Going to the background applies nothing")
    func scenePhaseBackgroundAppliesNothing() {
        let toApply = ReaderBrightness.onScenePhaseChange(to: .background, readerBrightness: 0.4)

        #expect(toApply == nil, "Backgrounding wrote a brightness change that reads nowhere.")
    }

    @Test("A return to the foreground with no reader brightness applies nothing")
    func scenePhaseActiveWithNoReaderBrightnessAppliesNothing() {
        let toApply = ReaderBrightness.onScenePhaseChange(to: .active, readerBrightness: nil)

        #expect(
            toApply == nil,
            "A reader who never touched the slider has nothing to reassert on return."
        )
    }
}
