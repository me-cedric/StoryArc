import Testing

@testable import Playback
import StoryArcCore

/// Where the word a stopped voice owes is armed, and where it is spent.
///
/// `ebook-reader`, *Opening a different publication*: "the listener is told once that the voice
/// stopped, rather than discovering it by silence". `VoiceStoppedNoticeTests` pins the value's
/// own arithmetic; this pins the seam — that of the four ways a session ends, exactly one arms
/// the notice, and only when what it ended was a voice.
///
/// **The seam is `PlayerCentre.displace()`**, reached from `prepareReadAloud` when a reader
/// opens over a running session and from `begin` when a second book starts. `end()` is the
/// listener's own stop and the book running out; `lostAudio()` is the platform taking the
/// audio for good. Neither owes a word, and both are asserted not to.
///
/// **What is asserted is the title, never the sentence.** `swift build` copies an `.xcstrings`
/// without compiling it, so `String(localized:)` answers with the key on the host — see
/// `PlayerLabels`. Android pins the same table in `SpokenAudioTest`, case for case.
@MainActor
@Suite("Where a stopped voice's word is armed")
struct PlayerDisplacementTests {

    /// A synthesised voice reading an EPUB: the only session that owes a word.
    private func speakingTheLongField(_ centre: PlayerCentre) {
        centre.begin(.stub(id: "long-field", title: "The Long Field"), source: PlaybackSourceDouble(.spoken))
    }

    /// A narrated file. Never owes one.
    private func narratingSeaRoom(_ centre: PlayerCentre) {
        centre.begin(
            .stub(id: "sea-room", title: "Sea Room", format: .m4b),
            source: PlaybackSourceDouble(.narrated)
        )
    }

    @Test("Nothing is owed while nothing has been displaced")
    func nothingYet() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)
        #expect(centre.voiceStopped == .none)
    }

    /// The reader's seam: a publication opening over a voice.
    @Test("Displacing a voice owes a word naming the book that went quiet")
    func displacingAVoice() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)

        centre.displace()

        #expect(centre.voiceStopped.isPending)
        #expect(centre.voiceStopped.title == "The Long Field")
        #expect(!centre.isRunning, "Displacing ends the session as well as arming the word.")
    }

    /// `audio-playback` calls the source "a fact about the file". A narrator that stops when
    /// you open another book is an event a reader already understands.
    @Test("Displacing a narrator owes nothing")
    func displacingANarrator() {
        let centre = PlayerCentre()
        narratingSeaRoom(centre)

        centre.displace()

        #expect(centre.voiceStopped == .none)
        #expect(!centre.isRunning)
    }

    /// The shelf's seam: an audiobook started while a voice speaks. `begin` ends the outgoing
    /// book itself, and that ending is a displacement.
    @Test("A second book beginning over a voice owes the word")
    func beginningOverAVoice() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)

        narratingSeaRoom(centre)

        #expect(centre.voiceStopped.title == "The Long Field")
        #expect(
            centre.book?.publication.displayTitle == "Sea Room",
            "The incoming book plays; the word is about the outgoing one."
        )
    }

    @Test("A voice beginning over a narrator owes nothing")
    func beginningOverANarrator() {
        let centre = PlayerCentre()
        narratingSeaRoom(centre)

        speakingTheLongField(centre)

        #expect(centre.voiceStopped == .none)
    }

    /// Starting the book already playing is a restart, not a displacement — nothing went
    /// quiet that the listener is not looking at.
    @Test("Beginning the same book again is a restart and owes nothing")
    func restartingTheSameBook() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)

        speakingTheLongField(centre)

        #expect(centre.voiceStopped == .none)
        #expect(centre.isRunning)
    }

    /// Opening the book being spoken adopts the session. The caller asks the handover before it
    /// displaces, so nothing here is reached — and the notice stays as it was.
    @Test("Adopting the running session owes nothing")
    func adopting() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)

        let spoken = centre.book?.id ?? ""
        #expect(centre.handover(opening: spoken) == .adopt)
        #expect(centre.voiceStopped == .none)
    }

    /// The listener who stopped the voice knows they did.
    @Test("The listener's own stop owes nothing")
    func listenerStops() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)

        centre.end()

        #expect(centre.voiceStopped == .none)
    }

    /// The highlight withdrawn and the transport gone is its own announcement.
    @Test("A book running out owes nothing")
    func runningOut() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.spoken)
        centre.begin(.stub(id: "long-field", title: "The Long Field"), source: source)

        source.runOut()

        #expect(centre.hasReachedTheEnd)
        #expect(centre.voiceStopped == .none)
    }

    /// Audio taken for good is the platform telling them.
    @Test("Audio taken by the platform owes nothing")
    func audioTaken() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)

        centre.lostAudio()

        #expect(centre.voiceStopped == .none)
    }

    /// The surface's half of *once*: what it takes, it spends. A second look — the same screen
    /// redrawn, or a return to it — finds nothing.
    @Test("Taking the notice gives it once and leaves nothing for a second render")
    func takenOnce() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)
        centre.displace()

        let shown = centre.takeVoiceStopped()

        #expect(shown.title == "The Long Field")
        #expect(centre.voiceStopped == .none)
        #expect(centre.takeVoiceStopped() == .none)
    }

    /// One word per stopping, not one word ever.
    @Test("A second displacement arms a second word")
    func displacedTwice() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)
        centre.displace()
        _ = centre.takeVoiceStopped()

        centre.begin(.stub(id: "harbour-02", title: "Harbour Lights 02"), source: PlaybackSourceDouble(.spoken))
        centre.displace()

        #expect(centre.voiceStopped.title == "Harbour Lights 02")
    }

    /// A narrator displaced while a voice's word is still owed must not take that word away:
    /// only a pending notice is ever written.
    @Test("A narrator's displacement leaves an unshown voice's word standing")
    func narratorDoesNotClearAPendingWord() {
        let centre = PlayerCentre()
        speakingTheLongField(centre)
        narratingSeaRoom(centre)
        #expect(centre.voiceStopped.title == "The Long Field")

        centre.displace()

        #expect(centre.voiceStopped.title == "The Long Field")
    }
}
