import SwiftUI
import Testing

@testable import DesignSystem

/// The app's haptic vocabulary, which is the platform's own.
///
/// `native-experience` lists haptics among the system affordances the app must use rather than
/// invent. `Haptics.swift` says the same thing in its own words — "`SensoryFeedback`, never a
/// `UIImpactFeedbackGenerator` of our own: SwiftUI's vocabulary is the one the device tunes for
/// its own Taptic Engine, and it is silent when the reader has turned system haptics off" — and
/// nothing asserted it. A hand-rolled buzz would be neither tuned nor silent, and it compiles.
///
/// What this cannot see is a wrist. `swift test` runs on the host with no Taptic Engine, so the
/// claim asserted here is the mapping: each moment in the vocabulary resolves to one of
/// SwiftUI's own signals, and the two moments resolve to different ones.
///
/// Android's `HapticsTest` puts the same two questions to `HapticFeedbackConstants`.
@Suite("The haptic vocabulary is the platform's")
struct HapticsTests {

    @Test("A finished thing plays the system's own success")
    func completionIsTheSystemSuccess() {
        #expect(StoryArcFeedback.completion.signal == .success)
    }

    @Test("A request the app cannot honour plays the system's own warning")
    func refusalIsTheSystemWarning() {
        #expect(StoryArcFeedback.refusal.signal == .warning)
    }

    /// And the two do not feel the same.
    ///
    /// A vocabulary that has collapsed onto one signal still plays a haptic at both moments,
    /// so neither assertion above catches it on its own — the end of a publication and a page
    /// turn refused at the first page would then be indistinguishable by touch, which is the
    /// only sense either of them is for.
    @Test("A new letter under the finger plays the system's own selection tick")
    func selectionIsTheSystemSelection() {
        #expect(StoryArcFeedback.selection.signal == .selection)
    }

    @Test("No two moments feel the same")
    func theMomentsDiffer() {
        let signals = StoryArcFeedback.allCases.map(\.signal)

        #expect(signals.count == 3)
        for (index, signal) in signals.enumerated() {
            #expect(!signals.dropFirst(index + 1).contains(signal))
        }
    }
}
