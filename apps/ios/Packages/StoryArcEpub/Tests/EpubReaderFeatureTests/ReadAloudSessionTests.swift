import Testing

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
}
