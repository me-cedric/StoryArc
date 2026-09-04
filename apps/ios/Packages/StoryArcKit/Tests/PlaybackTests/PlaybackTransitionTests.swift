import Foundation
import Testing

import StoryArcCore

@testable import Playback

/// What a pause means, and what ends it.
///
/// This is the whole decision playing a book makes, and the engine around it is the
/// platform's contract rather than this project's. Android pins the same cases in the same
/// order in `ReadAloudSessionTest`.
///
/// **These tests moved here from `EpubReaderFeatureTests` with the table they assert**, and
/// the move is worth more than the rename. `pnpm check` runs `test:ios`, which is
/// `StoryArcKit`'s host suites, and `test:ios:epub` is in no gate at all — so this table,
/// the one that decides whether a book starts talking on its own after a phone call, was
/// asserted by a suite nothing ran automatically. It runs on the host now, with no
/// simulator, in the gate.
@Suite("Playback session transitions")
struct PlaybackTransitionTests {

    private let idle = PlaybackSession()
    private var speaking: PlaybackSession { idle.started() }

    @Test("A session begins silent")
    func begins() {
        #expect(idle.state == .idle)
        #expect(!idle.isPlaying)
        #expect(!idle.isActive)
    }

    @Test("Starting speaks")
    func starting() {
        #expect(speaking.state == .playing)
        #expect(speaking.isPlaying)
        #expect(speaking.pausedBy == nil)
    }

    @Test("A reader's pause is recorded as the reader's")
    func readerPause() {
        let paused = speaking.pausedByListener()
        #expect(paused.state == .paused)
        #expect(paused.pausedBy == .listener)
    }

    @Test("A paused session still offers its controls")
    func pausedIsActive() {
        #expect(speaking.pausedByListener().isActive)
        #expect(!speaking.pausedByListener().isPlaying)
    }

    @Test("The reader can start it again")
    func readerResumes() {
        #expect(speaking.pausedByListener().resumed().state == .playing)
    }

    @Test("An interruption pauses and says so")
    func interruption() {
        let paused = speaking.interrupted()
        #expect(paused.state == .paused)
        #expect(paused.pausedBy == .interruption)
    }

    @Test("An interruption that ends well starts the voice again")
    func interruptionEnds() {
        #expect(speaking.interrupted().interruptionEnded(mayResume: true).state == .playing)
    }

    @Test("An interruption the platform will not resume leaves it paused")
    func interruptionEndsBadly() {
        let still = speaking.interrupted().interruptionEnded(mayResume: false)
        #expect(still.state == .paused)
        #expect(still.pausedBy == .interruption)
    }

    /// The case this type exists for: a notification must not undo a deliberate pause.
    @Test("An interruption never resumes a pause the reader made")
    func readerPauseSurvives() {
        let paused = speaking.pausedByListener()
        #expect(paused.interrupted() == paused)
        #expect(paused.interruptionEnded(mayResume: true) == paused)
    }

    @Test("Audio taken for good stops it rather than holding it")
    func lostForGood() {
        #expect(speaking.lostAudio().state == .idle)
        #expect(speaking.interrupted().lostAudio().state == .idle)
    }

    @Test("Nothing resumes a session that was never started")
    func idleIgnoresEverything() {
        #expect(idle.resumed() == idle)
        #expect(idle.pausedByListener() == idle)
        #expect(idle.interrupted() == idle)
    }

    @Test("Stopping clears the cause with the state")
    func stopping() {
        let stopped = speaking.interrupted().stopped()
        #expect(stopped.state == .idle)
        #expect(stopped.pausedBy == nil)
    }

    @Test("The lock screen names the chapter under the title")
    func label() {
        let label = SpokenLabel.of(title: "Sea Room", chapter: "Chapter Two", author: "Adam Nicolson")
        #expect(label.title == "Sea Room")
        #expect(label.detail == "Chapter Two")
    }

    @Test("A book with no navigation falls back to its author")
    func labelFallsBack() {
        #expect(SpokenLabel.of(title: "Sea Room", chapter: nil, author: "Adam Nicolson").detail == "Adam Nicolson")
        #expect(SpokenLabel.of(title: "Sea Room", chapter: "  ", author: "Adam Nicolson").detail == "Adam Nicolson")
    }

    @Test("A book with neither says only its title")
    func labelHasNothingElse() {
        #expect(SpokenLabel.of(title: "Sea Room", chapter: nil, author: nil).detail == nil)
        #expect(SpokenLabel.of(title: "Sea Room", chapter: "", author: " ").detail == nil)
    }

    // MARK: - Audio taken, and audio taken for good

    /// The case that used to have no branch at all: the audio comes back but the platform
    /// says the voice may not, and the session sat paused with nothing able to start it.
    @Test("Audio taken for good ends the session rather than leaving it paused")
    func takenForGood() {
        #expect(speaking.interrupted().endingInterruption(mayResume: false) == .lost)
    }

    @Test("Audio given back starts an interruption's own pause again")
    func givenBack() {
        #expect(speaking.interrupted().endingInterruption(mayResume: true) == .resume)
    }

    /// Both halves of the same sentence in `ebook-reader`: a reader's pause is never
    /// *resumed* by an interruption ending, and audio taken for good still ends the
    /// session — because a session nothing can start is the thing the spec forbids.
    @Test("An interruption ending never restarts a pause the reader made")
    func readerPauseIsNotResumed() {
        let paused = speaking.pausedByListener()
        #expect(paused.endingInterruption(mayResume: true) == .nothing)
        #expect(paused.endingInterruption(mayResume: false) == .lost)
    }

    /// The one direction this table converts a cause in, and the case Android's half of
    /// 3.8 found: a listener who reaches for pause *during* a call has decided.
    ///
    /// The platform lets go of the audio at that point, so the interruption ends by itself —
    /// and a session still calling that pause the interruption's would start a book somebody
    /// had deliberately silenced. Android pins the same in `PlaybackSessionTest`.
    @Test("A pause the listener makes during an interruption becomes the listener's")
    func pauseDuringAnInterruptionIsTheListeners() {
        let paused = speaking.interrupted().pausedByListener()
        #expect(paused.pausedBy == .listener)
        #expect(paused.state == .paused)
        #expect(paused.endingInterruption(mayResume: true) == .nothing)
    }

    @Test("Nothing happens to a session that was never running")
    func idleIsNotInterrupted() {
        #expect(idle.endingInterruption(mayResume: true) == .nothing)
        #expect(idle.endingInterruption(mayResume: false) == .nothing)
    }

    // MARK: - One book at a time

    @Test("Opening a publication while nothing speaks starts silent")
    func handoverFromSilence() {
        #expect(SessionHandover.opening("sea-room", whilePlaying: nil) == .none)
    }

    /// Closing the publication mid-sentence and coming back to it: the reader picks the
    /// voice up rather than starting a second session on the same book.
    @Test("Reopening the book being spoken adopts the session")
    func handoverToTheSameBook() {
        #expect(SessionHandover.opening("sea-room", whilePlaying: "sea-room") == .adopt)
    }

    @Test("Opening a different book displaces the voice")
    func handoverToAnotherBook() {
        #expect(SessionHandover.opening("the-peregrine", whilePlaying: "sea-room") == .displace)
    }

    // MARK: - The transport outside the reader

    private var book: SpokenBook {
        SpokenBook(
            publication: Publication(
                identity: identity,
                format: .epub,
                displayTitle: "Sea Room",
                authors: ["Adam Nicolson"],
                origin: .embedded
            ),
            url: URL(fileURLWithPath: "/books/sea-room.epub"),
            chapter: "Chapter Two"
        )
    }

    /// The hard constraint of the docked transport, as a value: absence is not a hidden
    /// view or an empty one, it is nothing at all, so the accessory slot the shell holds
    /// stays closed and the tab bar keeps its ordinary height.
    @Test("No session, no transport")
    func noTransportWithoutASession() {
        #expect(CompactPlayer.of(idle, playing: book) == nil)
        #expect(CompactPlayer.of(speaking, playing: nil) == nil)
        #expect(CompactPlayer.of(idle, playing: nil) == nil)
    }

    @Test("A running session has a transport")
    func transportWhileRunning() {
        #expect(CompactPlayer.of(speaking, playing: book)?.isPlaying == true)
    }

    /// A pause is not an ending. The listener who paused still needs the play button, and
    /// a transport that vanished on pause would leave them with a session and no way to
    /// resume it outside the book.
    @Test("A paused session keeps its transport, and its play button")
    func transportWhilePaused() {
        let paused = CompactPlayer.of(speaking.pausedByListener(), playing: book)
        #expect(paused != nil)
        #expect(paused?.isPlaying == false)
    }

    /// Every way a session can end, and all three withdraw the transport: the listener
    /// stopped it, the audio was taken for good, and the book ran out of words. `ebook-reader`
    /// names each one, and they share a single answer because they share a single state.
    @Test("Every ending withdraws the transport")
    func transportGoesWithTheSession() {
        #expect(CompactPlayer.of(speaking.stopped(), playing: book) == nil)
        #expect(CompactPlayer.of(speaking.lostAudio(), playing: book) == nil)
        #expect(CompactPlayer.of(speaking.interrupted().stopped(), playing: book) == nil)
    }

    /// The transport and the lock screen say the same two things, from the same value —
    /// `ebook-reader` requires them to match, and one source is how they cannot drift.
    @Test("The transport says what the media controls say")
    func transportSaysWhatTheLockScreenSays() {
        let transport = CompactPlayer.of(speaking, playing: book)
        #expect(transport?.label == book.label)
        #expect(transport?.label.title == "Sea Room")
        #expect(transport?.label.detail == "Chapter Two")
    }

    /// The way back carries the publication and its bytes, so choosing the transport opens
    /// the same file rather than searching a library for something that looks like it — the
    /// listener may be three screens away from wherever the book was found.
    @Test("The way back carries the book's own bytes")
    func transportCarriesTheWayBack() {
        let transport = CompactPlayer.of(speaking, playing: book)
        #expect(transport?.book.url == book.url)
        #expect(transport?.book.publication.identity == identity)
    }

    /// The two halves of *getting back to the book*, composed: the transport hands the
    /// shell the publication it is speaking, and opening that publication is the case
    /// ``SessionHandover`` already answers with `adopt`. That is why the return does not
    /// stop the voice — there is no second session to start, and no restart to repeat a
    /// sentence with.
    @Test("Choosing the transport reopens the book the voice is on, and adopts it")
    func returningAdoptsRatherThanRestarts() throws {
        let transport = try #require(CompactPlayer.of(speaking, playing: book))
        let opened = transport.book.publication.id
        #expect(SessionHandover.opening(opened, whilePlaying: book.id) == .adopt)
    }

    private let identity = PublicationIdentity(normalizedPath: "/books/sea-room.epub")
}
