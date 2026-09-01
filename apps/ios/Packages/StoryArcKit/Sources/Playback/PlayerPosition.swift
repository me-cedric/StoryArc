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

    /// Writes down where the audio got to.
    ///
    /// On every move, not only when the session ends. A process the system reclaims gets no
    /// ending at all, and the only position that survives one is a position already written.
    internal func recordReached() { record(at: place) }

    /// Hands one place to whoever is storing positions, as the thing they have to store.
    ///
    /// Internal rather than private only because it lives in a second file; nothing outside
    /// this module calls it, and nothing should — the session decides when a position is
    /// worth writing, and a caller choosing its own moments is a caller that will pick the
    /// wrong one.
    internal func record(at place: PlaybackPlace) {
        guard let book else { return }
        onRecord?(
            ReachedListening(
                book: book,
                position: position(at: place),
                isFinished: hasReachedTheEnd
            )
        )
    }
}
