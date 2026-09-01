public import Foundation

// The sleep timer, and the only things that move it.
//
// Split out of `PlayerCentre` for the reason `PlayerPosition.swift` is: that file stays the
// *session* — who is playing, what silenced it, what the transport does — and this one stays
// the one question a listener falling asleep asks of it. They change for different reasons,
// which is the only reason worth splitting on. Android keeps the same concern in its own
// `SleepTimer.kt` and drives it from `PlaybackHost`.
//
// **This is where a shipped control that did nothing became one that works.** `setSleepTimer`
// stored a countdown and `sleepTimerElapsed` knew what to do with one, and nothing in the app
// connected the two: a listener set *Sleep in 30 minutes*, the remaining time never changed,
// and the audio never stopped. `audio-playback` forbids exactly that — "every control the
// player offers works, or is absent — none is present and refusing".
public extension PlayerCentre {

    /// Whether *end of chapter* can be honoured at all.
    ///
    /// `audio-playback`: "every control the player offers works, or is absent — none is
    /// present and refusing". A session being read aloud has no true duration, so there is no
    /// end of chapter to stop at, and the surface asks this rather than drawing a row that
    /// would do nothing. Android's chip asks the same question of its own `SleepTimer.of`.
    var canSleepAtEndOfChapter: Bool {
        SleepCountdown.of(.endOfChapter, playing: time) != nil
    }

    /// Sets, replaces or clears the sleep timer.
    ///
    /// A choice this session cannot honour leaves no timer set, for the reason
    /// ``SleepCountdown/of(_:playing:)`` gives.
    func setSleepTimer(_ timer: SleepTimer?) {
        sleep = timer.flatMap { SleepCountdown.of($0, playing: time) }
        // Full volume again, whether the listener cleared a timer or replaced one part way
        // through its fade.
        source?.setVolume(1)
        platform?.sleepTimerChanged(isRunning: sleep != nil)
        published()
    }

    /// One tick of the countdown, and the only thing that moves it.
    ///
    /// **The whole of the sleep timer's behaviour is here**, which is what makes it assertable:
    /// what drives this in the app is a wall clock on the platform's side of the line — see
    /// ``PlaybackPlatform/sleepTimerChanged(isRunning:)`` — and a test moves time by calling it.
    ///
    /// - Parameter seconds: how much time has passed.
    func tickSleepTimer(by seconds: TimeInterval = SleepCountdown.tick) {
        guard let sleep, session.isActive else { return }
        // A paused book is not falling asleep. The count holds where it is, which is what a
        // listener who paused to answer the door means by it.
        guard session.isPlaying else { return }

        let next = sleep.ticked(by: seconds, playing: time)
        self.sleep = next
        // Unconditionally, not only on the way down: a listener who skips back inside the
        // chapter has pushed an end-of-chapter timer's fade away again, and the audio has to
        // come back up with it.
        source?.setVolume(next.gain)
        if next.hasElapsed {
            sleepTimerElapsed()
        } else {
            published()
        }
    }

    /// The timer elapsed and the fade has finished.
    ///
    /// `audio-playback`: "the position at which it stopped is recorded, so resuming starts a
    /// little before it rather than where the fade ended" — which is
    /// ``SleepCountdown/recordedPlace(afterFadingAt:)``, and the reason the record below is
    /// not simply ``place``.
    ///
    /// **Written here rather than left to the next tick**, because the next tick only happens
    /// while something is playing and nothing is. Android's `PlaybackHost.fellAsleep` records
    /// it at the same moment for the same reason.
    func sleepTimerElapsed() {
        guard book != nil, session.isActive else { return }
        let rewound = SleepCountdown.recordedPlace(afterFadingAt: place)
        record(at: rewound)
        sleep = nil
        session = session.pausedByListener()
        source?.pause()
        source?.setVolume(1)
        // The live session goes back too, so pressing play does not start mid-word in a
        // stretch the listener already slept through. Only where the source has a clock to go
        // back on: ``PlaybackSource/seek(toPart:offset:)`` is documented as never being asked
        // of a synthesised voice, and for that source the record is the whole of the rewind.
        if time.isScrubbable { source?.seek(toPart: rewound.partIndex, offset: rewound.offset) }
        platform?.sleepTimerChanged(isRunning: false)
        published()
    }
}
