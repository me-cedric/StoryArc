public import Foundation

/// Something that produces spoken audio, whichever kind it is.
///
/// **This is the seam the whole change turns on.** `design.md`: "one protocol with two
/// implementations — a narrated file and a synthesised voice — and one session object the
/// surfaces observe. The surfaces never learn which implementation is behind them; that is
/// what makes 'both sources look the same' a structural property rather than a promise."
///
/// So there is deliberately no `kind`, no `isNarrated`, and nothing a view could switch on.
/// The two places the sources genuinely differ are declared as data rather than as identity:
/// ``parts`` may carry no duration, and ``skipUnit`` says what a skip moves. A surface reads
/// those; it never reads which class it is talking to.
///
/// `AnyObject` because an engine is a reference: `AVPlayer` on one side, Readium's
/// synthesizer on the other, and both are alive across the whole session.
@MainActor
public protocol PlaybackSource: AnyObject {
    /// Called whenever the audio moves, so the one session object can redraw.
    ///
    /// Set by ``PlayerCentre`` when it takes the source on, and cleared when it lets it go.
    /// A closure rather than a delegate protocol because there is exactly one observer and
    /// it is always the centre — a second observer would be a second session.
    var moved: (@MainActor () -> Void)? { get set }

    /// Called when the source reaches the end by itself.
    ///
    /// `audio-playback` requires the end to withdraw everything — the media controls, the
    /// compact bar — rather than "offering to play a book that has run out of words". The
    /// source cannot do that itself: it does not know what a compact bar is.
    var ended: (@MainActor () -> Void)? { get set }

    /// The parts, in playing order.
    ///
    /// Never empty for a source that has begun: `audio-playback` requires a publication with
    /// no chapter markers to list "its parts in playing order instead, rather than showing
    /// an empty list", so a single unchaptered file reports one part rather than none.
    var parts: [PlaybackPart] { get }

    /// Where the audio is now.
    var place: PlaybackPlace { get }

    /// What one press of a skip control moves here. See ``SkipUnit``.
    var skipUnit: SkipUnit { get }

    /// How many parts could not be decoded.
    ///
    /// `publication-formats`: a damaged audiobook "plays what it can and states how much it
    /// could not … in the player's own controls rather than interrupting playback". Zero for
    /// a whole file, which is the ordinary case.
    var unreadablePartCount: Int { get }

    func play()
    func pause()
    func stop()
    func setSpeed(_ speed: PlaybackSpeed)

    /// How loud, 0…1, for the sleep timer's fade.
    ///
    /// `audio-playback`: playback "fades out rather than cutting off when it elapses".
    ///
    /// **It has a default, and the default is the honest answer for one of the two sources.**
    /// A narrated file has a volume to ramp mid-utterance. A synthesised voice does not —
    /// `AVSpeechUtterance.volume` applies to the *next* utterance rather than the one being
    /// spoken, so a voice fades in steps, one sentence quieter than the last, rather than
    /// smoothly. D19 settles that as the voice's half of this requirement:
    /// ``SpokenSource/setVolume(_:)`` in `StoryArcEpub` is the override; this default is for a
    /// source with nothing to apply it to.
    func setVolume(_ gain: Double)

    /// Stops playback no later than the end of the sentence or part already in progress.
    ///
    /// D19: a synthesised voice's sleep timer "stops at the end of the current sentence"
    /// rather than mid-word — `pause()` cannot promise that, because `AVSpeechSynthesizer`
    /// has no sentence-aware pause and ``PlaybackSource/pause()`` stops wherever the engine
    /// happens to be. The default calls ``pause()`` immediately, which is the right answer
    /// for a source with a clock: the fade in ``setVolume(_:)`` has already finished by the
    /// time the timer calls this, so there is nothing left to protect by waiting.
    func stopAtSentenceEnd()

    /// Move to a point inside a part.
    ///
    /// Only ever called where the part has a known duration — ``PlayerCentre`` will not ask
    /// a source that cannot answer, because `audio-playback` forbids a control that is
    /// "present and refusing".
    func seek(toPart index: Int, offset: TimeInterval)

    /// Move by an interval of seconds, or by one sentence.
    ///
    /// - Parameter interval: the seconds to move. A source whose ``skipUnit`` is
    ///   ``SkipUnit/sentence`` ignores it.
    ///
    /// The source, not the centre, decides what crossing a boundary does: `audio-playback`
    /// requires skipping past the start or end of a chapter to continue "into the
    /// neighbouring one rather than stopping at the boundary", and only the engine knows
    /// where the neighbour begins.
    func skip(_ direction: SkipDirection, by interval: TimeInterval)
}

public extension PlaybackSource {
    /// A source with no volume to ramp. See the requirement's own note.
    func setVolume(_ gain: Double) {}

    /// Stops now. See the requirement's own note on ``stopAtSentenceEnd()``.
    func stopAtSentenceEnd() { pause() }
}
