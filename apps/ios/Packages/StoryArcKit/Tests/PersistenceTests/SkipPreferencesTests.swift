import Foundation
import Testing

@testable import Persistence
@testable import Playback

/// What one press of a skip control moves, remembered.
///
/// `audio-playback` asks for an interval "the listener can configure", and until now iOS had
/// the model and no way to set it: `PlayerCentre.skipIntervals` had **no setter anywhere in the
/// app**, so every listener got the defaults for ever. Android's `SkipPreferences` is the
/// contract these mirror, case for case, so the two platforms cannot drift on what an unset
/// value means.
@Suite("Skip intervals survive the app being closed")
struct SkipPreferencesTests {

    private func store() -> SkipPreferences {
        SkipPreferences(defaults: UserDefaults(suiteName: "skip-\(UUID().uuidString)") ?? .standard)
    }

    @Test("A device that has never been asked gets the product's defaults")
    func neverAsked() {
        #expect(store().intervals() == .default)
    }

    @Test("A choice survives, because it is the whole point of the setting")
    func choiceSurvives() {
        let store = store()
        store.remember(SkipIntervals(back: 10, forward: 5))

        #expect(store.intervals() == SkipIntervals(back: 10, forward: 5))
    }

    /// The bug this prevents, and it is the same one Android's store records: zero is what an
    /// unwritten key reads as, **and** it is the one value a skip may never have — a control
    /// that moves nothing. So a half-written pair is the default pair rather than a stopped one.
    @Test("A half-written pair is the defaults, not a control that moves nothing")
    func halfWritten() {
        let store = store()
        store.remember(SkipIntervals(back: 10, forward: 0))

        #expect(store.intervals() == .default)
    }

    @Test("Both directions are remembered together, because they are one setting to a listener")
    func rememberedTogether() {
        let store = store()
        store.remember(SkipIntervals(back: 5, forward: 30))
        store.remember(SkipIntervals(back: 30, forward: 5))

        #expect(store.intervals() == SkipIntervals(back: 30, forward: 5))
    }

    @Test("Forgetting returns the defaults rather than nothing")
    func forgetting() {
        let store = store()
        store.remember(SkipIntervals(back: 5, forward: 5))
        store.forget()

        #expect(store.intervals() == .default)
    }

    /// The same four both platforms offer. A listener who sets 10 seconds on a phone and finds
    /// no 10 on a tablet is a listener the set has drifted under.
    @Test("The offered set is the one Android offers")
    func offeredSet() {
        #expect(SkipIntervals.offered == [5, 10, 15, 30])
    }

    @Test("An interval outside the offered set is still stored, because a value is a value")
    func unofferedValueIsKept() {
        // The picker cannot produce one, but a value read back from an older build can, and
        // silently rewriting a listener's stored choice is worse than honouring it.
        let store = store()
        store.remember(SkipIntervals(back: 45, forward: 45))

        #expect(store.intervals() == SkipIntervals(back: 45, forward: 45))
    }
}
