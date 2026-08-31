// What playing a book is, with no engine in it.
//
// This table was `ReadAloudSession` in `StoryArcEpub`, written for the speech synthesizer
// and correct for it. `audiobooks-and-playback` asks for one player behind both a narrator
// and a synthesised voice, and the first thing the two share is this: what a *pause*
// means. So the type moved here rather than being copied — a second copy is a copy that
// can drift, and the interruption rule is the one nobody would notice drifting until a
// book started talking on its own during a phone call.
//
// A reader who pressed pause and a phone call that took the audio away both leave the
// audio silent, and they must not end the same way. When the call ends the book should
// carry on; when the listener pressed pause it must not.
//
// So the cause of the pause is carried with the pause, and the transitions live here where
// they can be asserted without a speaker. Android pins the same table in `ReadAloud.kt`.

/// Whether the audio is running, stopped, or holding.
public enum PlaybackState: Equatable, Sendable {
    case idle
    case playing
    case paused
}

/// Who silenced it, which decides whether the end of an interruption starts it again.
public enum PauseCause: Equatable, Sendable {
    /// The listener pressed pause. Nothing but the listener starts this again.
    case listener
    case interruption
}

/// The state of playback, and every way it can change.
///
/// A value rather than a class: each event returns the session that follows it, so a wrong
/// transition is something a test can compare rather than a field somebody forgot to clear.
public struct PlaybackSession: Equatable, Sendable {
    public private(set) var state: PlaybackState
    /// `nil` unless ``state`` is ``PlaybackState/paused``.
    public private(set) var pausedBy: PauseCause?

    public init(state: PlaybackState = .idle, pausedBy: PauseCause? = nil) {
        self.state = state
        self.pausedBy = pausedBy
    }

    /// Whether audio is coming out right now.
    public var isPlaying: Bool { state == .playing }

    /// Whether the transport controls belong on screen at all.
    ///
    /// Paused counts: a listener who paused still needs the play button, and skipping while
    /// paused is how somebody gets past a passage they do not want read.
    public var isActive: Bool { state != .idle }

    /// Starting, or restarting from a new position.
    public func started() -> PlaybackSession { PlaybackSession(state: .playing) }

    /// The listener pressed pause. Nothing but the listener starts this again.
    public func pausedByListener() -> PlaybackSession {
        isPlaying ? PlaybackSession(state: .paused, pausedBy: .listener) : self
    }

    /// Something else took the audio: a call, another app, a spoken direction.
    ///
    /// A pause the listener already made is left exactly as it was — otherwise a
    /// notification arriving during a deliberate pause would convert it into one that
    /// resumes on its own.
    public func interrupted() -> PlaybackSession {
        isPlaying ? PlaybackSession(state: .paused, pausedBy: .interruption) : self
    }

    /// The listener pressed play.
    public func resumed() -> PlaybackSession {
        state == .paused ? PlaybackSession(state: .playing) : self
    }

    /// The interruption is over.
    ///
    /// - Parameter mayResume: the platform's own answer — iOS puts it in the interruption
    ///   notification's options, Android in whether the focus came back at all. Playback
    ///   resumes only when the platform says so *and* the pause was the interruption's.
    public func interruptionEnded(mayResume: Bool) -> PlaybackSession {
        (mayResume && pausedBy == .interruption) ? resumed() : self
    }

    /// The audio is gone for good — another app took it and kept it.
    ///
    /// Stopped rather than paused: there is nothing to wait for, and a session that sat
    /// paused for ever would hold an audio session open for a book nobody is hearing.
    public func lostAudio() -> PlaybackSession { PlaybackSession() }

    /// The listener closed it, or the book ran out.
    public func stopped() -> PlaybackSession { PlaybackSession() }

    /// What the end of an interruption means for this session.
    ///
    /// Three answers, not two, and the missing third was a real defect: an ending the
    /// platform would not resume matched neither branch — so the session sat paused for
    /// ever, with no position written and nothing telling the listener. `audio-playback`
    /// names the case: "audio taken for good ends the session and records the position
    /// rather than leaving it paused for ever".
    ///
    /// - Parameter mayResume: the platform's own answer — iOS reads it from the
    ///   interruption notification's `shouldResume`, Android from whether the focus came
    ///   back at all rather than being taken outright.
    public func endingInterruption(mayResume: Bool) -> InterruptionOutcome {
        // Taken for good, and it ends the session whoever silenced it: a session left
        // paused with nothing able to start it is exactly what the spec forbids. That is
        // not the pause being *undone* — the other clause forbids resuming a pause the
        // listener made, and this never resumes one.
        guard mayResume else { return isActive ? .lost : .nothing }
        return pausedBy == .interruption ? .resume : .nothing
    }
}

/// What the end of an interruption does to a session.
///
/// A value rather than a branch inside each platform's audio callback, because the two
/// callbacks look nothing alike — one notification with an options bitmask on iOS, a stream
/// of focus changes on Android — and the decision underneath them is the same one. Android
/// pins these three in `ReadAloud.kt`.
public enum InterruptionOutcome: Equatable, Sendable {
    /// Nothing to do: the audio was not the interruption's to give back.
    case nothing
    /// The audio came back and the pause was the interruption's, so it carries on.
    case resume
    /// The audio is gone for good. The session ends, and its position is written first.
    case lost
}

/// What opening a publication does to audio that is already playing.
///
/// One session at a time. `audio-playback`: "the first stops and its position is recorded
/// before the second begins, because two books speaking at once is never what was meant".
///
/// The same question answers what a listener coming *back* to the book being played does:
/// it picks the session up rather than starting another. Both live here as a value so they
/// can be asserted without an engine, in the way the pause table already is. Android pins
/// the same three in `ReadAloud.kt`.
public enum SessionHandover: Equatable, Sendable {
    /// Nothing is playing. The publication opens silent, as it always did.
    case none
    /// The book being opened is the book being played, so the screen observes the session
    /// rather than starting another.
    case adopt
    /// A different book. The session ends where it reached and that position is written
    /// down before the new publication draws a word.
    case displace

    /// - Parameter playing: the identity of the book being played, or `nil` for silence.
    public static func opening(_ publication: String, whilePlaying playing: String?) -> SessionHandover {
        guard let playing else { return .none }
        return publication == playing ? .adopt : .displace
    }
}
