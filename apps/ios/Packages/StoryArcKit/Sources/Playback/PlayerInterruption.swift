// What the platform does to a session, as opposed to what a listener does.
//
// Its own file for the reason `PlayerSkip.swift` and `PlayerSleep.swift` have one:
// `PlayerCentre.swift` sits against SwiftLint's 400-line cap, and the cap keeps pointing at a
// real seam. The centre owns *what is playing* and what a listener asks of it; this file owns
// the events nobody in the app raises — a call arriving, headphones pulled out, another app
// taking the audio and keeping it. They change for different reasons, which is the only reason
// worth splitting on.
//
// The decisions themselves are `PlaybackSession`'s and are asserted without an audio session
// at all; what is here is the centre acting on them. Android keeps the same concern in
// `PlaybackFocus.kt`, which reads media3's three facts and maps them onto the same table.
public extension PlayerCentre {

    /// What the end of an interruption means, asked of the session rather than decided
    /// inside an audio callback. See ``PlaybackSession/endingInterruption(mayResume:)``.
    func endingInterruption(mayResume: Bool) -> InterruptionOutcome {
        session.endingInterruption(mayResume: mayResume)
    }

    /// Something else took the audio: a call, another app, a spoken direction.
    func interrupt() {
        guard session.isPlaying else { return }
        session = session.interrupted()
        source?.pause()
        published()
    }

    /// The audio came back, and the platform said playback may carry on.
    func resumeAfterInterruption() {
        let next = session.interruptionEnded(mayResume: true)
        guard next != session else { return }
        session = next
        source?.play()
        published()
    }

    /// Headphones were pulled out, so the audio would come out of the speaker.
    ///
    /// `audio-playback`: playback pauses "because a book suddenly playing out loud is never
    /// what was intended", and "it does not resume by itself when they are reconnected" —
    /// which is why the cause recorded is the listener's rather than an interruption's.
    /// Reconnecting the headphones raises no interruption-ended event at all, but a route
    /// change back would, and this is what makes that harmless.
    func routeLost() {
        guard session.isPlaying else { return }
        session = session.pausedByListener()
        source?.pause()
        published()
    }
}
