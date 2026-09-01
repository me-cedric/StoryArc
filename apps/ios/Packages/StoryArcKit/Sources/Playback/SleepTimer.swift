public import Foundation

/// When to stop, chosen by a listener who is falling asleep.
///
/// **The end-of-chapter option is a product decision**, recorded as one in `design.md`: a
/// music player has no reason to offer it, a book player does, and it is the option a
/// listener falling asleep actually wants — not to be cut off mid-sentence.
///
/// Two cases rather than a number, because the second one is not a duration at all: it is a
/// place in the book, and how long it is depends on where the listener is when they choose
/// it. Android's `SleepAfter` is the same two.
public enum SleepTimer: Sendable, Equatable {
    /// Stop after this much more listening.
    case after(TimeInterval)
    /// Stop when the current chapter ends, however long that is.
    case endOfChapter

    /// The durations offered beside *end of chapter*.
    ///
    /// **A product decision**, and these are Android's `OFFERED_MINUTES` to the minute.
    /// Neither Material nor Apple publishes a set, and a platform offering a sixth would be
    /// a platform where the same listener has a different set of choices — long enough to
    /// fall asleep in, short enough that the last one is not a whole evening.
    public static let durations: [TimeInterval] = [5, 15, 30, 45, 60].map { TimeInterval($0) * 60 }
}

/// A sleep timer that is running, and how much of it is left.
///
/// Immutable and engine-free, so the interesting parts — when it elapses, how loud the audio
/// is on the way there, and where the listener will start again — can be asserted without a
/// decoder and without waiting for real minutes to pass. What drives it is
/// ``PlayerCentre/tickSleepTimer(by:)``; what turns a wall clock into those calls is the
/// platform's, for the reason ``PlaybackPlatform/sleepTimerChanged(isRunning:)`` sets out.
///
/// **Both cases are held as one remaining time**, and the difference is only in what moves
/// it: a duration counts itself down, and *end of chapter* is re-read from where the audio
/// has reached. That keeps one number on the player — `audio-playback` asks for "the
/// remaining time" to be shown, and a surface that had to ask which kind of timer it was
/// would be the same branch drawn twice. Android's `SleepTimer` holds it the same way.
public struct SleepCountdown: Sendable, Equatable {
    public let timer: SleepTimer

    /// Seconds left.
    ///
    /// Not optional, and that is the requirement rather than a simplification: a timer that
    /// cannot be honoured is never made at all — see ``of(_:playing:)``.
    public let remaining: TimeInterval

    public init(timer: SleepTimer, remaining: TimeInterval) {
        self.timer = timer
        self.remaining = remaining
    }

    /// How long the audio takes to go quiet, and how far back the listener starts again.
    ///
    /// **One number for both, and that is the argument for it**: the fade is exactly the
    /// stretch a listener stopped taking in, so starting again where the fade *began* is
    /// starting at the last thing they properly heard. `audio-playback` asks for "a little
    /// before" and does not say how little; thirty seconds is a **product decision** with no
    /// guideline behind it, and it is the number Android holds under `FADE_MILLIS`.
    public static let fade: TimeInterval = 30

    /// How far back from the end of the fade the position is written. See ``fade``.
    ///
    /// Computed rather than a second stored constant so the two cannot drift, and computed
    /// rather than `= fade` because this file's neighbour records what one static let
    /// initialised from another cost: ``PlaybackSpeed`` deadlocked inside `dispatch_once` on
    /// the first `PlayerCentre()` anything made.
    public static var rewind: TimeInterval { fade }

    /// How often the countdown looks at the clock.
    ///
    /// Short enough that the fade is a fade rather than a staircase — half a second of a
    /// thirty-second ramp is a step of about two per cent — and long enough that a sleeping
    /// phone is not woken sixty times a second. Android's `TICK_MILLIS` is the same.
    public static let tick: TimeInterval = 0.5

    /// Whether it is time to stop.
    public var hasElapsed: Bool { remaining <= 0 }

    /// How loud the audio should be, 0…1.
    ///
    /// `audio-playback`: "playback fades out rather than cutting off when it elapses". A
    /// straight ramp over the last ``fade`` seconds, because a listener who is nearly asleep
    /// should not be woken by silence arriving all at once.
    public var gain: Double {
        guard remaining < Self.fade else { return 1 }
        guard remaining > 0 else { return 0 }
        return min(1, max(0, remaining / Self.fade))
    }

    /// The timer a moment later.
    ///
    /// - Parameters:
    ///   - seconds: how much time has passed.
    ///   - time: where the audio has reached, for ``SleepTimer/endOfChapter``.
    ///
    /// End of chapter is **re-read** rather than counted down: a listener who skips forward
    /// inside the chapter has moved the end nearer, and a timer that kept its own count would
    /// stop them in the middle of the next one. A part that has lost its length keeps the
    /// count it had — the source that reported no duration is not the source that said the
    /// listener has arrived.
    public func ticked(by seconds: TimeInterval, playing time: PlaybackTime) -> SleepCountdown {
        switch timer {
        case .after:
            SleepCountdown(timer: timer, remaining: max(0, remaining - seconds))
        case .endOfChapter:
            SleepCountdown(timer: timer, remaining: Self.leftInPart(time) ?? remaining)
        }
    }

    /// A timer for what the listener chose, or **`nil`** when it cannot be honoured.
    ///
    /// `nil` for *end of chapter* where nothing knows how long the part is — a session being
    /// read aloud has no true duration, and `audio-playback` requires that every control the
    /// player offers "works, or is absent — none is present and refusing". So the surface
    /// asks ``PlayerCentre/canSleepAtEndOfChapter`` rather than drawing an option that would
    /// do nothing, which is what Android's null from `SleepTimer.of` says to its chip.
    public static func of(_ timer: SleepTimer, playing time: PlaybackTime) -> SleepCountdown? {
        switch timer {
        case let .after(seconds):
            seconds > 0 ? SleepCountdown(timer: timer, remaining: seconds) : nil
        case .endOfChapter:
            leftInPart(time).map { SleepCountdown(timer: timer, remaining: $0) }
        }
    }

    /// Where to record having stopped, given where the fade ended.
    ///
    /// Clamped at the start of the part rather than reaching into the one before it: a
    /// listener who fell asleep in the first half-minute of a chapter starts that chapter
    /// again, which is the honest reading of "a little before".
    public static func recordedPlace(afterFadingAt place: PlaybackPlace) -> PlaybackPlace {
        PlaybackPlace(partIndex: place.partIndex, offset: max(0, place.offset - rewind))
    }

    /// How much of the current part is left, when the source says how long it is.
    private static func leftInPart(_ time: PlaybackTime) -> TimeInterval? {
        guard let total = time.total else { return nil }
        return max(0, total - time.elapsed)
    }
}
