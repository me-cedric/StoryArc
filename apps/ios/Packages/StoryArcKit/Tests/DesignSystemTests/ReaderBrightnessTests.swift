import SwiftUI
import Testing

@testable import DesignSystem

/// `reading-themes`, *Brightness is reader-local*, for both readers.
///
/// One suite where there were two: the comic reader's and the EPUB reader's modifiers were
/// mirrors, and so were their tests.
@Suite("Brightness across a reader's lifecycle")
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

/// `foldables-and-iphone-duo` D6: the store reads and writes the screen it is handed, never
/// `UIScreen.main`. On an iPhone Duo that is the screen of the reader's own scene.
@MainActor
@Suite("Brightness goes through the reader's own screen")
struct BrightnessStoreTests {
    private final class Screen: BrightnessScreen {
        var level: Double { didSet { writes.append(level) } }
        private(set) var writes: [Double] = []
        init(level: Double) { self.level = level }
    }

    @Test("The level is read from the injected screen, and every write lands on it")
    func readsAndWritesTheInjectedScreen() {
        let screen = Screen(level: 0.7)
        let store = BrightnessStore(screen: screen)

        #expect(store.level == 0.7)
        store.apply(0.3)
        store.sceneChanged(to: .active, readerBrightness: 0.4)
        store.depart(readerBrightness: 0.4, captured: 0.7)
        store.depart(readerBrightness: nil, captured: 0.7)

        #expect(screen.writes == [0.3, 0.4, 0.7], "the writes were \(screen.writes)")
    }

    @Test("With no screen the level is full and nothing is written")
    func noScreen() {
        let store = BrightnessStore(screen: nil)

        #expect(store.level == 1)
        store.apply(0.3)
    }
}
