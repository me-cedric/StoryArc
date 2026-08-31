public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared

public import Persistence
public import StoryArcCore

/// The voice, which outlives the screen that started it.
///
/// `ebook-reader`: "the session SHALL outlive the screen it was started from", and closing
/// the publication returns the listener to what they were doing "rather than being kept in
/// the book". Until this existed the session belonged to ``EpubReaderModel`` and the
/// reader's `onDisappear` killed it, so leaving the book was leaving the audio.
///
/// **Where this lives, and why here.** It is a process-wide singleton rather than any
/// screen's state, because that is the only lifetime longer than every screen. It lives in
/// this module rather than a new one because it holds Readium's synthesizer and ADR-0005
/// keeps Readium behind this package — which also rules out `StoryArcCore`. It is *public*
/// because the transport that survives the reader is drawn above every feature: the app
/// layer already depends on this module to present the reader, so it can observe the
/// session without any feature module learning about another, which the module layout
/// forbids.
///
/// **What it owns and what it does not.** It owns the synthesizer, the sentence cursor, the
/// media controls, the interruption contract and the position writer — everything that has
/// to survive a screen. It does not own the highlight or the page: those need a navigator,
/// so a reader that happens to be on screen registers as ``follower`` and is let go without
/// a word when it disappears.
///
/// The platform seam — what the lock screen says, and what an interruption does — is in
/// `ReadAloudControls.swift`. Android needs no equivalent type: its session already lives
/// in a `mediaPlayback` foreground service, and `ReadAloudHost` there does this routing.
@MainActor
@Observable
public final class ReadAloudCentre {

    /// The one session there can be.
    ///
    /// `ebook-reader` allows exactly one: "two books cannot be read aloud at once". A
    /// singleton is that requirement, stated where it cannot be worked around.
    public static let shared = ReadAloudCentre()

    // MARK: - What a listener can see

    /// Whether the voice is running, and what silenced it if it is not.
    ///
    /// Internal, and deliberately: what silenced the voice is this module's business, and a
    /// transport above it needs only the two answers below. Exposing the cause would invite
    /// a surface outside to decide what a pause means, which is the one decision
    /// ``ReadAloudSession`` exists to keep in one place.
    private(set) var session = ReadAloudSession()

    /// The book being spoken, or `nil` when nothing is.
    ///
    /// What a transport says, and where its way back goes. Nil is also the answer to "is
    /// there a transport at all": `ebook-reader` requires that when no session is running
    /// "no transport is present anywhere in the app, and no space is reserved for one".
    public private(set) var book: SpokenBook?

    /// Whether a transport belongs on screen at all.
    public var isRunning: Bool { session.isActive }

    /// Whether a sentence is being spoken right now.
    public var isSpeaking: Bool { session.isSpeaking }

    // MARK: - What it holds

    /// The sentence being spoken. Internal, because it is Readium's.
    private(set) var spoken: Locator?

    /// The reader drawing the sentence, while one is on screen.
    ///
    /// Weak, and that is the whole of the ownership change: the session refers to the
    /// screen, never the other way round, so a reader going away cannot take the voice
    /// with it.
    @ObservationIgnored weak var follower: EpubReaderModel?

    @ObservationIgnored private var speech: PublicationSpeechSynthesizer?
    @ObservationIgnored private var position: SpokenPosition?
    /// The audio-interruption observation, taken down with the session rather than with a
    /// screen. Internal because `ReadAloudControls.swift` is what puts it up.
    @ObservationIgnored var interruptions: (any NSObjectProtocol)?
    /// Whether the lock screen's buttons have been wired. See ``wireRemoteCommands()``.
    @ObservationIgnored var isWired = false

    /// Readium's delegate, held here for the life of the process.
    ///
    /// Held by the centre rather than by the reader that built the synthesizer: Readium
    /// keeps its delegate weakly, so one owned by a screen would be deallocated the moment
    /// the screen was — and the voice would carry on with nothing listening to it, which is
    /// a session that can never end itself.
    @ObservationIgnored let speechDelegate = SpeechObserver()

    private init() {}

    // MARK: - Starting, and changing hands

    /// Takes a session over from the reader that started it.
    ///
    /// Everything the session needs afterwards is passed in here, because after this call
    /// the reader is free to disappear: the engine, where to write the position, and what
    /// to say about the book. The follower is the one thing that is allowed to go.
    func begin(
        _ book: SpokenBook,
        speaking speech: PublicationSpeechSynthesizer,
        recording position: SpokenPosition,
        drawnBy follower: EpubReaderModel,
        from locator: Locator?
    ) {
        self.book = book
        self.speech = speech
        self.position = position
        self.follower = follower
        wireRemoteCommands()
        observeInterruptions()
        session = session.started()
        speech.start(from: locator)
        publishNowPlaying()
    }

    /// A reader has opened the book that is being spoken, and will draw its sentence.
    func adopt(_ follower: EpubReaderModel) {
        guard book?.id == follower.publication.id else { return }
        self.follower = follower
    }

    /// The screen drawing the sentence has gone.
    ///
    /// The session is not touched. That is the change: `onDisappear` used to end it, and
    /// now it only says that nobody is drawing. The highlight goes with the navigator that
    /// held it, and comes back when a reader adopts the session again.
    func release(_ follower: EpubReaderModel) {
        guard self.follower === follower else { return }
        self.follower = nil
    }

    /// Draws the sentence again for a reader that has just adopted the session.
    ///
    /// `ebook-reader`: "reopening the publication resumes at the sentence being spoken,
    /// without the voice stopping or repeating".
    func redrawSpokenSentence() async {
        guard let spoken else { return }
        await follower?.drawSpokenSentence(spoken)
    }

    // MARK: - The transport

    /// Pause and play, from wherever the listener reached for it.
    public func toggle() {
        guard let speech else { return }
        if session.isSpeaking {
            session = session.pausedByReader()
            speech.pause()
        } else {
            session = session.resumed()
            speech.resume()
        }
        publishNowPlaying()
    }

    /// The next sentence, and the one before.
    ///
    /// Skipping while paused starts speaking again, which is what the gesture means:
    /// nobody skips a sentence in order to keep hearing silence.
    public func skip(forward: Bool) {
        guard session.isActive, let speech else { return }
        session = session.started()
        if forward { speech.next() } else { speech.previous() }
        publishNowPlaying()
    }

    /// Ends the session: the listener closed it, or the book ran out of words.
    public func end() { finish(with: session.stopped()) }

    // MARK: - What the platform does to it

    /// What the end of an interruption means, asked of the session rather than decided
    /// inside the audio callback. See ``ReadAloudSession/endingInterruption(mayResume:)``.
    func endingInterruption(mayResume: Bool) -> InterruptionOutcome {
        session.endingInterruption(mayResume: mayResume)
    }

    /// Something else took the audio: a call, another app, a spoken direction.
    func interrupt() {
        guard session.isSpeaking else { return }
        session = session.interrupted()
        speech?.pause()
        publishNowPlaying()
    }

    /// The audio came back, and the platform said the voice may carry on.
    func resumeAfterInterruption() {
        let next = session.interruptionEnded(mayResume: true)
        guard next != session else { return }
        session = next
        speech?.resume()
        publishNowPlaying()
    }

    /// Ends the session because the audio was taken and not given back.
    ///
    /// Named apart from ``end()`` because the cause is the difference worth reading at the
    /// call site, not the state that follows — both leave a silent, controlless session,
    /// and `ebook-reader` asks for both by name.
    func lostAudio() { finish(with: session.lostAudio()) }

    /// The one way a session stops.
    ///
    /// The position first, always. `ebook-reader`: when the session cannot continue "the
    /// position the voice reached is recorded first" — and a teardown that cleared the
    /// cursor before writing it would lose exactly the hour this change exists to keep.
    private func finish(with next: ReadAloudSession) {
        guard session.isActive || book != nil else { return }
        recordReached()
        session = next
        speech?.stop()
        speech = nil
        position = nil
        book = nil
        spoken = nil
        stopObservingInterruptions()
        clearNowPlaying()
        follower?.withdrawSpokenHighlight()
        follower = nil
    }

    // MARK: - What the voice is on

    /// Readium's report, and everything that follows from it.
    func speechAdvanced(to state: PublicationSpeechSynthesizer.State) async {
        switch state {
        case .stopped:
            // Readium stops itself at the end of the publication. Everything a listener's
            // own stop does has to happen here too, or the media controls keep offering to
            // play a book that has run out of words.
            guard session.isActive else { return }
            end()

        case let .paused(utterance):
            await reached(utterance.locator)

        case let .playing(utterance, range):
            // The range is the word being said inside the sentence. The sentence is what
            // gets drawn: a highlight that moved word by word over a paragraph is a
            // karaoke line, and this is a book.
            _ = range
            await reached(utterance.locator)
        }
        publishNowPlaying()
    }

    private func reached(_ locator: Locator) async {
        spoken = locator
        book?.chapter = locator.title ?? book?.chapter
        recordReached()
        await follower?.drawSpokenSentence(locator)
    }

    /// Writes down where the voice got to.
    ///
    /// On every sentence, not only when the session ends. A process the system reclaims
    /// gets no ending at all, and the only position that survives one is a position already
    /// written. While a reader is on screen its navigator writes at this same rate, because
    /// the page follows the voice; this is that rate carrying on after the screen has gone.
    private func recordReached() {
        guard let position, let spoken else { return }
        let reached = position.reached(spoken)
        guard reached.isRecordable else { return }
        Task { await position.record(reached) }
    }
}

/// Where a session's position goes, with no screen involved.
///
/// Everything the writer needs is copied out of the reader when the session begins, so the
/// write does not depend on a model, a navigator or a view that may be long gone by the
/// time the voice reaches the sentence being recorded.
struct SpokenPosition: Sendable {
    let identity: PublicationIdentity
    /// The reading order's hrefs, which is what turns a locator into a percentage.
    let readingOrder: [String]
    let store: ProgressStore?

    /// Turns Readium's locator into the position `reading-progress` records.
    func reached(_ locator: Locator) -> ReachedPosition {
        ReachedPosition(
            locator: (try? locator.jsonString()) ?? "",
            // The rule lives in `StoryArcCore` so both platforms answer it the same way,
            // and because it is subtler than it looks: in scroll mode Readium reports
            // `0.0` rather than nothing.
            progression: TotalProgression.resolve(
                reported: locator.locations.totalProgression,
                within: locator.locations.progression ?? 0,
                resourceIndex: TotalProgression.index(of: locator.href.string, in: readingOrder),
                resourceCount: readingOrder.count
            )
        )
    }

    func record(_ reached: ReachedPosition) async {
        guard let store else { return }
        try? await store.save(reached.record(for: identity, at: Date()))
    }
}
