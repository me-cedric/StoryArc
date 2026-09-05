import Testing

@testable import Playback

/// Being told **once** that the voice stopped.
///
/// `ebook-reader`, *Opening a different publication*:
///
/// > **AND** the listener is told once that the voice stopped, rather than discovering it by
/// > silence
///
/// The clause had no owner until 2026-09-05. It needs a sentence never written on either
/// platform, and `read-aloud-beyond-the-reader` task 5.5's rule sends every new string to the
/// vocabulary slice — whose scope, as drafted, promotes *existing* literals and does not take a
/// new one. The owner placed it here: this change ships the one key with its four translations.
/// See that task list's 1.4 and 5.5.
///
/// **What is asserted here is the arithmetic, not the sentence.** `once` is the load-bearing
/// word, and it is the only part of this that a screen cannot be trusted with: a flag left
/// standing is shown again on every return, and nothing about that looks wrong in a screenshot.
/// Android pins the same table in `VoiceStoppedNoticeTest`, case for case.
@Suite("The word a stopped voice owes")
struct VoiceStoppedNoticeTests {

    @Test("Nothing is owed before anything happens")
    func nothingYet() {
        #expect(!VoiceStoppedNotice.none.isPending)
    }

    @Test("Displacing a voice owes the listener a word")
    func displacingAVoice() {
        #expect(VoiceStoppedNotice.displacing(aVoice: true).isPending)
    }

    /// A narrator that stops when you open another book is an event a reader already
    /// understands. `ebook-reader`'s scenario says *the voice*, and only the voice.
    @Test("Displacing a narrated book owes nothing")
    func displacingANarrator() {
        #expect(VoiceStoppedNotice.displacing(aVoice: false) == .none)
        #expect(!VoiceStoppedNotice.displacing(aVoice: false).isPending)
    }

    /// The whole of *once*. The surface that shows the word is not the surface that armed it,
    /// and on a return to the screen it is the only one still running — so the notice has to be
    /// spent by being given rather than by being remembered.
    @Test("Told once: taking the notice leaves nothing to tell")
    func toldOnce() {
        let owed = VoiceStoppedNotice.displacing(aVoice: true)
        #expect(owed.isPending)
        #expect(!owed.taken().isPending)
    }

    @Test("Returning again still finds nothing to tell")
    func toldOnceAndNotAgain() {
        let given = VoiceStoppedNotice.displacing(aVoice: true).taken()
        #expect(!given.taken().isPending)
        #expect(given.taken().taken() == .none)
    }

    /// One word per stopping, not one word ever. A listener whose voice is displaced a second
    /// time has a second thing to be told about.
    @Test("A second displacement owes a second word")
    func toldAgainAfterASecondStopping() {
        let given = VoiceStoppedNotice.displacing(aVoice: true).taken()
        #expect(!given.isPending)
        #expect(VoiceStoppedNotice.displacing(aVoice: true).isPending)
    }
}
