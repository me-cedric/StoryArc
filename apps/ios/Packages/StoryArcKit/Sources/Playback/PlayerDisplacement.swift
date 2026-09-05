public import Foundation

// What opening another publication does to the session running, and the word it owes.
//
// Split out of `PlayerCentre` for the reason `PlayerSleep.swift` is: that file stays the
// *session* — who is playing, what silenced it, what the transport does — and this one stays
// the one ending that has an audience somewhere else. They change for different reasons.
// Android keeps the same concern in `SpokenAudio.silence` and holds the notice there, because
// there the arbiter is a separate object and here the centre is the arbiter.
public extension PlayerCentre {

    /// Ends the session because another publication is opening.
    ///
    /// Named apart from ``end()`` and ``lostAudio()`` for the reason those two are apart: the
    /// cause is the difference worth reading at the call site, and this is the one cause that
    /// owes a listener a word. `ebook-reader`: opening a different publication while the voice
    /// is speaking ends the session, records the position, **and** tells the listener once that
    /// the voice stopped "rather than discovering it by silence". A listener who pressed stop,
    /// a book that ran out and audio the platform took all go through the other two, and none
    /// of them arms anything — see ``VoiceStoppedNotice``.
    ///
    /// **Whether it was a voice is a fact about the file.** `audio-playback` calls a listener's
    /// source "a fact about the file, stated once where the publication is described", and
    /// ``PlayerWayBack`` already decides its question on `publication.format` for that reason.
    /// So does this: a voice reads a publication that is not audio, a narrator plays one that
    /// is, and nothing here asks which ``PlaybackSource`` was behind the sound — which is the
    /// property `design.md` makes structural and this must not be the first to break.
    ///
    /// Armed before the ending, so the notice is standing by the time the screen that caused
    /// the displacement asks for it. Only a pending notice is written: a narrator displaced
    /// while a voice's word is still owed does not take that word away.
    func displace() {
        if let book {
            let owed = VoiceStoppedNotice.displacing(
                aVoice: !book.publication.format.isAudio,
                of: book.publication.displayTitle
            )
            if owed.isPending { voiceStopped = owed }
        }
        end()
    }

    /// The notice, given to the surface that asked — and spent by the asking.
    ///
    /// Returns what was owed and leaves ``voiceStopped`` at ``VoiceStoppedNotice/none``, which
    /// is the whole of *once*: the EPUB reader takes it in the same run of the main actor that
    /// displaced, so the shell behind it never sees a pending notice; the shell takes it when an
    /// audiobook started from the shelf displaced a voice and no reader is on screen. A return
    /// to either finds nothing to say.
    func takeVoiceStopped() -> VoiceStoppedNotice {
        let owed = voiceStopped
        voiceStopped = owed.taken()
        return owed
    }
}
