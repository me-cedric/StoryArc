public import Foundation

public import StoryArcCore

// What a session writes down.
//
// Split out of `PlayerCentre` so that file stays the *session* — who is playing, what
// silenced it, what the transport does — and this one stays the one question
// `reading-progress` asks of it: where the listener got to, and whether the book is
// finished. They change for different reasons, which is the only reason worth splitting on.
//
// Android's half of the same seam is `PlaybackHost.recordPosition`.

/// How many seconds of audio may pass with no other moment to write at.
///
/// The same fifteen seconds Android's `PlayingBook.TICK_MILLIS` holds, and the same number
/// `ReadingProgress` describes its own timestamp as moving on by.
private let recordFloor: TimeInterval = 15

public extension PlayerCentre {

    /// The reading position a place in this session is.
    ///
    /// `reading-progress`: "an offset in time within a named part, and a percentage is
    /// derived from the total duration". The part's length is passed through rather than
    /// filled in with a zero when nothing knows it — see
    /// ``ReadingPosition/listening(part:partCount:offset:of:)``, where the whole reason that
    /// field is optional is written down.
    func position(at place: PlaybackPlace) -> ReadingPosition {
        .listening(
            part: place.partIndex,
            partCount: parts.count,
            offset: place.offset,
            of: parts.indices.contains(place.partIndex) ? parts[place.partIndex].duration : nil
        )
    }

    /// Writes down where the audio got to, whatever brought it there.
    ///
    /// Not only when the session ends. A process the system reclaims gets no ending at all,
    /// and the only position that survives one is a position already written. So
    /// `audio-playback` names the moments and this is every one of them that the listener
    /// caused: a pause, a skip, a scrub, a chapter chosen from a list, and the app leaving
    /// the foreground. ``PlayerCentre/finish(with:)`` calls it for each of the three endings.
    ///
    /// Public, because the app owns the one moment this object cannot see — the scene leaving
    /// `active`. Android's half is `MainActivity.onStop`.
    func recordReached() { record(at: place) }

    /// The clock moved. A write only where it has moved far enough to be worth one.
    ///
    /// **The floor, and the reason there is one.** ``NarratedSource`` reports its place four
    /// times a second, so a write on every report was four writes a second into SwiftData for
    /// the length of a book. That is a different defect from a stale position, and it hides
    /// the same fix: events plus a floor is the shape, not a write on every frame.
    ///
    /// Measured in the audio's own seconds rather than by a clock, which keeps the rule
    /// independent of playback speed and lets a test assert it without waiting. A part change
    /// always writes: crossing a chapter is a landmark, and the offset restarts at it.
    internal func recordDrifted() {
        guard let last = recorded else { return recordReached() }
        guard place.partIndex != last.partIndex || place.offset - last.offset >= recordFloor
        else { return }
        recordReached()
    }

    /// A jump the listener chose: the source moves, then exactly one write.
    ///
    /// The write cannot come first — it would carry the place the listener just left. And it
    /// cannot be left to ``recordDrifted()``, whose floor swallows a short jump: a chapter
    /// chosen from the list, or a scrub of a few seconds, would write nothing at all. So the
    /// report the move itself makes is passed over, and this writes once in its place.
    ///
    /// `audio-playback` names "a jump the listener chose" as a moment to write at, and names
    /// it once. Two writes for one jump is the defect this shape exists to make impossible.
    internal func jumped(_ move: () -> Void) {
        isJumping = true
        move()
        isJumping = false
        recordReached()
    }

    /// Hands one place to whoever is storing positions, as the thing they have to store.
    ///
    /// Internal rather than private only because it lives in a second file; nothing outside
    /// this module calls it, and nothing should — the session decides when a position is
    /// worth writing, and a caller choosing its own moments is a caller that will pick the
    /// wrong one.
    internal func record(at place: PlaybackPlace) {
        guard let book else { return }
        recorded = place
        onRecord?(
            ReachedListening(
                book: book,
                position: position(at: place),
                isFinished: hasReachedTheEnd
            )
        )
    }
}
