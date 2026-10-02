internal import Playback

/// What opening a comic or a PDF does to a voice already speaking — a narrated audiobook or
/// an EPUB being read aloud.
///
/// D18. `ebook-reader`, *Opening a different publication*: opening one "ends the session at a
/// sentence boundary [or, for a narrator, wherever it has reached] and the position it reached
/// is recorded before the new publication opens", and the listener is told once rather than
/// discovering it by silence.
///
/// **Only ever a silence, never a claim.** A comic and a PDF cannot themselves be read aloud,
/// so the publication opening here is never the one a session could be adopted for —
/// ``PlayerCentre/handover(opening:)`` answers `.none` or `.displace` and this never sees
/// `.adopt`. `EpubReaderModel/prepareReadAloud` is the reflowable reader's own copy of the same
/// seam, and does see `.adopt`, because an EPUB can be the thing speaking.
///
/// A free function rather than a method on ``ReaderModel``, so `ReaderVoiceHandoverTests` can
/// assert it without building a reader around a corpus file. `PlayerDisplacementTests` already
/// pins ``PlayerCentre/displace()`` and ``PlayerCentre/handover(opening:)`` themselves — what
/// counts as a voice, what the notice says, that it arms once — so only the wiring, that
/// opening this reader asks at all, belongs here.
enum ReaderVoiceHandover {
    /// Ends the session speaking a different publication, if one is, and returns the word it
    /// owes — `nil` when nothing was displaced.
    @MainActor
    static func displaceIfNeeded(opening publication: String, centre: PlayerCentre) -> VoiceStoppedNotice? {
        guard centre.handover(opening: publication) == .displace else { return nil }
        centre.displace()
        return centre.takeVoiceStopped()
    }
}
