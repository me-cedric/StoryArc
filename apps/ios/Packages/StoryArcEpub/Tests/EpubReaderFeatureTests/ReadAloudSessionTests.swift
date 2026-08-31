import Foundation
import Testing

import StoryArcCore

@testable import EpubReaderFeature

/// What a pause means, and what ends it.
///
/// This is the whole decision reading aloud makes, and the engine around it is the
/// platform's contract rather than this project's. Android pins the same cases in the
/// same order in `ReadAloudSessionTest`.
@Suite("Read aloud session")
struct ReadAloudSessionTests {

    private let idle = ReadAloudSession()
    private var speaking: ReadAloudSession { idle.started() }

    @Test("A session begins silent")
    func begins() {
        #expect(idle.state == .idle)
        #expect(!idle.isSpeaking)
        #expect(!idle.isActive)
    }

    @Test("Starting speaks")
    func starting() {
        #expect(speaking.state == .speaking)
        #expect(speaking.isSpeaking)
        #expect(speaking.pausedBy == nil)
    }

    @Test("A reader's pause is recorded as the reader's")
    func readerPause() {
        let paused = speaking.pausedByReader()
        #expect(paused.state == .paused)
        #expect(paused.pausedBy == .reader)
    }

    @Test("A paused session still offers its controls")
    func pausedIsActive() {
        #expect(speaking.pausedByReader().isActive)
        #expect(!speaking.pausedByReader().isSpeaking)
    }

    @Test("The reader can start it again")
    func readerResumes() {
        #expect(speaking.pausedByReader().resumed().state == .speaking)
    }

    @Test("An interruption pauses and says so")
    func interruption() {
        let paused = speaking.interrupted()
        #expect(paused.state == .paused)
        #expect(paused.pausedBy == .interruption)
    }

    @Test("An interruption that ends well starts the voice again")
    func interruptionEnds() {
        #expect(speaking.interrupted().interruptionEnded(mayResume: true).state == .speaking)
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
        let paused = speaking.pausedByReader()
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
        #expect(idle.pausedByReader() == idle)
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
        let paused = speaking.pausedByReader()
        #expect(paused.endingInterruption(mayResume: true) == .nothing)
        #expect(paused.endingInterruption(mayResume: false) == .lost)
    }

    @Test("Nothing happens to a session that was never running")
    func idleIsNotInterrupted() {
        #expect(idle.endingInterruption(mayResume: true) == .nothing)
        #expect(idle.endingInterruption(mayResume: false) == .nothing)
    }

    // MARK: - One book at a time

    @Test("Opening a publication while nothing speaks starts silent")
    func handoverFromSilence() {
        #expect(SessionHandover.opening("sea-room", whileSpeaking: nil) == .none)
    }

    /// Closing the publication mid-sentence and coming back to it: the reader picks the
    /// voice up rather than starting a second session on the same book.
    @Test("Reopening the book being spoken adopts the session")
    func handoverToTheSameBook() {
        #expect(SessionHandover.opening("sea-room", whileSpeaking: "sea-room") == .adopt)
    }

    @Test("Opening a different book displaces the voice")
    func handoverToAnotherBook() {
        #expect(SessionHandover.opening("the-peregrine", whileSpeaking: "sea-room") == .displace)
    }

    // MARK: - Where the listening got to

    private let sentence = #"{"href":"/chapter-4.xhtml","type":"text/html"}"#

    /// The path that can lose an hour. What the session hands the progress store is the
    /// sentence the voice reached, as an opaque locator — never a page number, which a
    /// reflowable book does not have.
    @Test("The reached position is recorded as the sentence, not as a page")
    func reachedPositionIsRecorded() {
        let record = ReachedPosition(locator: sentence, progression: 0.42)
            .record(for: identity, at: moment)
        #expect(record.identity == identity)
        #expect(record.position == .reflowable(progression: 0.42, locator: sentence))
        #expect(record.updatedAt == moment)
        #expect(!record.isFinished)
    }

    /// The end of the publication is the end of the content, not a page count.
    @Test("Listening to the last sentence finishes the book")
    func reachedTheEnd() {
        let end = ReachedPosition(locator: sentence, progression: 1)
        let nearlyThere = ReachedPosition(locator: sentence, progression: 0.9989)
        #expect(end.record(for: identity, at: moment).isFinished)
        #expect(!nearlyThere.record(for: identity, at: moment).isFinished)
    }

    /// A session the process is reclaimed under writes nothing more, so what was written
    /// on the way has to stand on its own — and an empty locator would stand for nothing.
    @Test("A sentence with no locator is not written over a good position")
    func nothingWorthRecording() {
        #expect(!ReachedPosition(locator: "", progression: 0.42).isRecordable)
        #expect(ReachedPosition(locator: sentence, progression: 0).isRecordable)
    }

    private let identity = PublicationIdentity(normalizedPath: "/books/sea-room.epub")
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)
}
