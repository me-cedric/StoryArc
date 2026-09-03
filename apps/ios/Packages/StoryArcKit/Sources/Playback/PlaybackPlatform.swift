/// The platform's own half of a playback session.
///
/// Four moments, because there are four: the session started and the app should claim the
/// audio, something changed and the lock screen should say so, the session ended and both
/// should be given back — and a sleep timer began or stopped needing a clock.
///
/// A protocol rather than a concrete type so ``PlayerCentre`` stays host-testable: there is
/// no `AVAudioSession` and no `MPNowPlayingInfoCenter` on the machine `pnpm test:ios` runs
/// on, and a centre that reached for either directly could be asserted nowhere.
@MainActor
public protocol PlaybackPlatform: AnyObject {
    /// Claim the audio and start listening for the platform taking it away.
    func sessionBegan()
    /// Something a listener could see has changed.
    func published()
    /// Give the audio back and take the book off the lock screen.
    func sessionEnded()

    /// A sleep timer was set, replaced or cleared.
    ///
    /// **The wall clock is on this side of the line, and that is deliberate.** The countdown
    /// has to keep running while the listener is asleep with the screen off, which is a real
    /// clock — and a real clock is the one thing a host test must not have: a thirty-second
    /// fade asserted in real time is thirty seconds of a unit test, and a thirty-minute timer
    /// is not assertable at all. So the ticking lives here, beside the audio session, and the
    /// whole of the behaviour — the count, the ramp, the elapsing, the rewind — is
    /// ``PlayerCentre/tickSleepTimer(by:)``, asserted without one.
    ///
    /// Android puts its countdown in `PlaybackHost` because a `CoroutineScope` is already
    /// there and its unit tests drive `SleepTimer` directly rather than the host. Same split,
    /// each platform's own seam.
    ///
    /// - Parameter isRunning: whether a timer is now counting. `false` releases the clock —
    ///   a clock left running after the timer is spent is a phone woken twice a second for
    ///   nothing.
    func sleepTimerChanged(isRunning: Bool)

    /// The listener changed how far a skip moves, so the system's own controls must be told.
    ///
    /// `MPRemoteCommandCenter` publishes its `preferredIntervals` once, when the commands are
    /// wired. Without this the full player would say ten seconds and the lock screen would go on
    /// saying fifteen — and `audio-playback` requires the interval to be "stated on the control
    /// itself", which makes that a defect on two controls rather than a stale label on one.
    ///
    /// Defaulted, because a platform that publishes no remote commands has nothing to update and
    /// the host tests run with no platform at all.
    func skipIntervalsChanged(_ intervals: SkipIntervals)
}

public extension PlaybackPlatform {
    func skipIntervalsChanged(_ intervals: SkipIntervals) {}
}

/// The audio session and the lock screen, as one thing to hand ``PlayerCentre``.
///
/// The two are separate types because they answer to different frameworks and change for
/// different reasons; they are wired together here because a session that claimed the audio
/// and never published, or published and never claimed, is broken in a way neither type can
/// see on its own.
@MainActor
public final class SystemPlaybackPlatform: PlaybackPlatform {
    private let audio: PlaybackAudioSession
    private let nowPlaying: NowPlaying
    private weak var centre: PlayerCentre?

    /// The sleep timer's clock, while one is set. See
    /// ``PlaybackPlatform/sleepTimerChanged(isRunning:)``.
    private var countdown: Task<Void, Never>?

    public init(for centre: PlayerCentre) {
        self.centre = centre
        audio = PlaybackAudioSession(driving: centre)
        nowPlaying = NowPlaying(publishing: centre)
    }

    public func sessionBegan() { audio.begin() }

    public func published() { nowPlaying.publish() }

    public func sessionEnded() {
        sleepTimerChanged(isRunning: false)
        nowPlaying.clear()
        audio.end()
    }

    /// Starts or releases the clock that moves the countdown.
    ///
    /// An unstructured `Task` because its lifetime is the timer's rather than any caller's:
    /// the listener sets a timer from a sheet they then dismiss, and the count has to outlive
    /// the screen exactly as the session does. Cancelled rather than left to finish, so a
    /// replaced timer never leaves two clocks running against one countdown.
    ///
    /// `Task.sleep` rather than a `Timer`: the interval is half a second and the drift a
    /// coalesced timer would introduce over a thirty-minute count is real, whereas a suspended
    /// task costs nothing while it waits.
    /// Re-publishes the intervals the lock screen states.
    ///
    /// `wire()` sets `preferredIntervals` once when the commands are created, so a listener who
    /// changes the interval afterwards would otherwise see the old number on every system
    /// surface until the next session.
    public func skipIntervalsChanged(_ intervals: SkipIntervals) {
        #if os(iOS)
        nowPlaying.republishSkipIntervals(intervals)
        #endif
    }

    public func sleepTimerChanged(isRunning: Bool) {
        countdown?.cancel()
        countdown = nil
        guard isRunning else { return }
        countdown = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SleepCountdown.tick))
                guard !Task.isCancelled, let centre = self?.centre, centre.sleep != nil else { return }
                centre.tickSleepTimer(by: SleepCountdown.tick)
            }
        }
    }
}

public extension PlayerCentre {

    /// Gives this centre the platform's own half, once.
    ///
    /// Both sources start a session from a different place — a narrated book from the shelf,
    /// a spoken one from inside the reader — and both owe the same audio session and the same
    /// lock screen. Made once and kept: wiring them per session is how a listener who has
    /// started five books ends up with five handlers on every lock-screen button.
    ///
    /// Never called from a host test, which is why ``PlayerCentre/platform`` stays optional
    /// rather than being built in `init()`: there is no `AVAudioSession` and no
    /// `MPNowPlayingInfoCenter` on the machine `pnpm test:ios` runs on.
    func adoptSystemPlatform() {
        guard platform == nil else { return }
        platform = SystemPlaybackPlatform(for: self)
    }
}
