public import Foundation

public import Playback

/// How far one press of a skip control moves, remembered across launches.
///
/// **`audio-playback` asks for an interval "the listener can configure", and iOS had no way to
/// configure it.** `PlayerCentre.skipIntervals` existed, was read by the player, the lock screen
/// and the timeline — and had **no setter anywhere in the app**, so every listener got the
/// product defaults for ever and the requirement's second clause was unmet without anything
/// failing. This is that setter's other half.
///
/// Android's `SkipPreferences` is the contract this mirrors, case for case rather than in
/// shape: the two platforms must agree on what an unset value means, or a listener with both
/// gets two answers to one setting.
/// Not `Sendable`, and deliberately so: `UserDefaults` is not, and the neighbouring
/// `PlaybackPreferences` makes the same choice for the same reason. A store is constructed where
/// it is used rather than passed across an isolation boundary.
public struct SkipPreferences {

    private let defaults: UserDefaults
    private let prefix = "app.storyarc.playback.skip"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// What the listener chose, or the defaults on a device that has never been asked.
    ///
    /// **Read as a pair, and a half-written pair is the defaults.** `UserDefaults` answers `0`
    /// for a key that was never written, and zero is also the one value a skip may never have —
    /// a control that moves nothing is a control that does nothing. There is no sentinel that
    /// separates the two, so an unusable half makes the whole reading unusable and the defaults
    /// stand. Android's store says the same thing about `SharedPreferences`, for the same
    /// reason.
    public func intervals() -> SkipIntervals {
        let back = defaults.double(forKey: key("back"))
        let forward = defaults.double(forKey: key("forward"))
        guard back > 0, forward > 0 else { return .default }
        return SkipIntervals(back: back, forward: forward)
    }

    /// Remembers a choice. Both directions together: to a listener they are one setting.
    public func remember(_ intervals: SkipIntervals) {
        defaults.set(intervals.back, forKey: key("back"))
        defaults.set(intervals.forward, forKey: key("forward"))
    }

    /// Back to the defaults.
    public func forget() {
        defaults.removeObject(forKey: key("back"))
        defaults.removeObject(forKey: key("forward"))
    }

    private func key(_ direction: String) -> String { "\(prefix).\(direction)" }
}
