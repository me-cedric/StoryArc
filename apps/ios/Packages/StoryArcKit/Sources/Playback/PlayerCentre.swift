public import Foundation

public import StoryArcCore

/// The one session there can be, and the only thing a surface talks to.
///
/// `audio-playback`: "The app SHALL present a single playback surface, and every source of
/// spoken audio — a narrated audiobook and the read-aloud voice alike — SHALL drive that
/// one surface." This is where that stops being a promise. There is one of these, it holds
/// one ``PlaybackSource``, and nothing it publishes says which kind of source that is.
///
/// **What it owns and what it does not.** It owns the session state, the book, the parts,
/// the place, the speed, the skip intervals and the sleep timer — everything that has to
/// survive a screen. It does not own an engine, an audio session, or a now-playing centre:
/// those are the platform's, and they sit either side of this in
/// `NarratedSource` and in the app layer.
///
/// **Not a singleton, unlike ``ReadAloudCentre`` before it.** The app makes one and hands it
/// down, because the thing that made a singleton necessary there — a session started deep
/// inside a reader with no way to reach the shell — is answered here by the shell owning the
/// centre and passing it in. A test can then make its own, which is the whole reason this
/// type is host-testable at all.
@MainActor
@Observable
public final class PlayerCentre {

    // MARK: - What a listener can see

    /// Whether audio is running, and what silenced it if it is not.
    ///
    /// Private-set and read through the two questions below: what silenced the audio is this
    /// type's business, and a surface needs only "is there a session" and "is it playing".
    /// Exposing the cause would invite a view to decide what a pause means, which is the one
    /// decision ``PlaybackSession`` exists to keep in one place.
    public private(set) var session = PlaybackSession()

    /// The book being played, or `nil` when nothing is.
    public private(set) var book: SpokenBook?

    /// The parts, in playing order. Empty when nothing is playing.
    public private(set) var parts: [PlaybackPart] = []

    /// Where the audio is.
    public private(set) var place: PlaybackPlace = .start

    /// How fast, remembered per publication by whoever wired ``onRecallSpeed``.
    public private(set) var speed: PlaybackSpeed = .normal

    /// How far a skip goes. See ``SkipIntervals`` for why the defaults are what they are.
    public var skipIntervals: SkipIntervals = .default

    /// The sleep timer, while one is set.
    public private(set) var sleep: SleepCountdown?

    /// How many parts of this book could not be decoded.
    ///
    /// `publication-formats`: a damaged audiobook "plays what it can and states how much it
    /// could not … in the player's own controls rather than interrupting playback".
    public private(set) var unreadablePartCount = 0

    /// Whether a compact bar belongs on screen at all.
    ///
    /// The narrow question, kept apart from ``compact`` on purpose. A shell that decides
    /// whether to open its accessory slot should depend on *this*, which changes when a
    /// listener starts, pauses or ends a session — not on the book, whose chapter is
    /// rewritten every time the audio crosses a part. Reading the wrong one redraws the
    /// whole navigation for hours.
    public var isRunning: Bool { session.isActive }

    /// Whether audio is coming out right now.
    public var isPlaying: Bool { session.isPlaying }

    /// Everything the compact bar draws, or `nil` when there is nothing to draw.
    public var compact: CompactPlayer? { CompactPlayer.of(session, playing: book) }

    /// The part being played.
    public var currentPart: PlaybackPart? {
        parts.indices.contains(place.partIndex) ? parts[place.partIndex] : nil
    }

    /// The position, and whether there is a total to state beside it.
    ///
    /// The whole of the narrated-versus-spoken difference, in one value. See ``PlaybackTime``.
    public var time: PlaybackTime {
        PlaybackTime(elapsed: place.offset, total: currentPart?.duration)
    }

    // MARK: - What the app wires in

    /// Where a session's position goes.
    ///
    /// A closure rather than a store, because `Playback` has no business knowing about
    /// SwiftData: `reading-progress` owns the record and the app layer owns the wiring. It
    /// is called on every part change, whenever a session ends, and — the case that matters
    /// — *before* a second book displaces the first.
    public var onRecord: (@MainActor (SpokenBook, PlaybackPlace) -> Void)?

    /// The speed to start a publication at.
    ///
    /// `audio-playback`: speed "is remembered for that publication and offered as the default
    /// for others in the same series". The remembering is the app's; the asking is here.
    public var onRecallSpeed: (@MainActor (Publication) -> PlaybackSpeed?)?

    /// A speed the listener chose, to be remembered against this publication.
    public var onRememberSpeed: (@MainActor (Publication, PlaybackSpeed) -> Void)?

    /// What one press of a skip control moves here.
    ///
    /// Read by the surfaces and by the lock screen so each states the right thing — seconds
    /// for a narrated file, a sentence for a voice. It is data about the source, not the
    /// source's identity: nothing may branch on *which* implementation is behind it, and
    /// this is the honest way to ask the one question that genuinely differs.
    public var skipUnit: SkipUnit { source?.skipUnit ?? .time }

    /// The platform's own half of a session: the audio session, and the lock screen.
    ///
    /// Optional, and `nil` in every host test — an audio session cannot be interrupted from
    /// one, and a `MPNowPlayingInfoCenter` does not exist there. Held here rather than
    /// wired by the app so that publishing cannot be forgotten at one of the eleven places
    /// this object changes: every one of them ends in ``published()``.
    @ObservationIgnored public var platform: (any PlaybackPlatform)?

    /// Gives this centre the platform's own half, once.
    ///
    /// Both sources start a session from a different place — a narrated book from the shelf,
    /// a spoken one from inside the reader — and both owe the same audio session and the same
    /// lock screen. Made once and kept: wiring them per session is how a listener who started
    /// five books ends up with five handlers on every lock-screen button.
    ///
    /// Never called from a host test, which is why ``platform`` stays optional rather than
    /// being built in ``init()``: there is no `AVAudioSession` and no `MPNowPlayingInfoCenter`
    /// on the machine `pnpm test:ios` runs on.
    public func adoptSystemPlatform() {
        guard platform == nil else { return }
        platform = SystemPlaybackPlatform(for: self)
    }

    @ObservationIgnored private var source: (any PlaybackSource)?

    /// The one session there can be.
    ///
    /// A process-wide singleton for the reason `ReadAloudCentre.shared` is one: the session
    /// has to outlive every screen, and that is a lifetime no screen's state has.
    /// `audio-playback` allows exactly one — "the first stops and its position is recorded
    /// before the second begins" — and a singleton is that requirement stated where it
    /// cannot be worked around.
    ///
    /// The initialiser stays public so a test makes its own. Every suite in `PlaybackTests`
    /// does, which is the whole reason this type is host-testable.
    public static let shared = PlayerCentre()

    public init() {}

    // MARK: - Starting, and changing hands

    /// Takes a book on, displacing whatever was playing.
    ///
    /// `audio-playback`: "the first stops and its position is recorded before the second
    /// begins". ``end()`` writes the position, so the order below is the requirement — not a
    /// tidy-up that happens to come first.
    public func begin(_ book: SpokenBook, source: any PlaybackSource) {
        if self.book != nil { end() }

        self.source = source
        parts = source.parts
        place = source.place
        unreadablePartCount = source.unreadablePartCount
        self.book = book.naming(title(ofPartAt: place.partIndex))
        speed = onRecallSpeed?(book.publication) ?? .normal

        source.moved = { [weak self] in self?.sourceMoved() }
        source.ended = { [weak self] in self?.end() }
        source.setSpeed(speed)

        session = session.started()
        source.play()
        platform?.sessionBegan()
        published()
    }

    /// What opening a publication should do to the session already running.
    ///
    /// The caller asks before it opens, so a reader returning to the book being played can
    /// pick the session up rather than starting a second one on the same book.
    public func handover(opening publication: String) -> SessionHandover {
        SessionHandover.opening(publication, whilePlaying: book?.id)
    }

    // MARK: - The transport

    /// Pause and play, from wherever the listener reached for it.
    public func toggle() {
        guard let source else { return }
        if session.isPlaying {
            session = session.pausedByListener()
            source.pause()
        } else {
            session = session.resumed()
            source.play()
        }
        published()
    }

    /// Move by the listener's configured interval, or by one sentence.
    ///
    /// Skipping while paused starts playing again, which is what the gesture means: nobody
    /// skips back in order to keep hearing silence.
    public func skip(_ direction: SkipDirection) {
        guard session.isActive, let source else { return }
        session = session.started()
        source.skip(direction, by: skipIntervals.interval(direction))
        source.play()
        published()
    }

    /// Move to a point inside the part being played.
    ///
    /// Ignored where the part has no known duration. `audio-playback` forbids a control that
    /// is "present and refusing", so the surface does not offer a scrubber there at all —
    /// this guard is the same rule stated where a caller cannot forget it.
    public func scrub(to offset: TimeInterval) {
        guard time.isScrubbable, let source else { return }
        source.seek(toPart: place.partIndex, offset: offset)
    }

    /// Move to a part from the chapter list.
    public func play(part index: Int) {
        guard session.isActive, let source, parts.indices.contains(index) else { return }
        session = session.started()
        source.seek(toPart: index, offset: 0)
        source.play()
        published()
    }

    /// Change speed without changing pitch — the pitch half is the engine's, in
    /// `NarratedSource`.
    public func setSpeed(_ speed: PlaybackSpeed) {
        self.speed = speed
        source?.setSpeed(speed)
        if let book { onRememberSpeed?(book.publication, speed) }
        published()
    }

    // MARK: - The sleep timer

    /// Sets, replaces or clears the sleep timer.
    public func setSleepTimer(_ timer: SleepTimer?) {
        guard let timer else {
            sleep = nil
            return
        }
        sleep = SleepCountdown(timer: timer, remaining: remaining(of: timer))
    }

    /// The timer elapsed and the fade has finished.
    ///
    /// `audio-playback`: "the position at which it stopped is recorded, so resuming starts a
    /// little before it rather than where the fade ended" — which is
    /// ``SleepCountdown/recordedPlace(afterFadingAt:)``, and the reason the record below is
    /// not simply ``place``.
    public func sleepTimerElapsed() {
        guard let book, session.isActive else { return }
        onRecord?(book, SleepCountdown.recordedPlace(afterFadingAt: place))
        sleep = nil
        session = session.pausedByListener()
        source?.pause()
        published()
    }

    private func remaining(of timer: SleepTimer) -> TimeInterval? {
        switch timer {
        case let .after(seconds):
            seconds
        case .endOfChapter:
            currentPart?.duration.map { max(0, $0 - place.offset) }
        }
    }

    // MARK: - What the platform does to it

    /// What the end of an interruption means, asked of the session rather than decided
    /// inside an audio callback. See ``PlaybackSession/endingInterruption(mayResume:)``.
    public func endingInterruption(mayResume: Bool) -> InterruptionOutcome {
        session.endingInterruption(mayResume: mayResume)
    }

    /// Something else took the audio: a call, another app, a spoken direction.
    public func interrupt() {
        guard session.isPlaying else { return }
        session = session.interrupted()
        source?.pause()
        published()
    }

    /// The audio came back, and the platform said playback may carry on.
    public func resumeAfterInterruption() {
        let next = session.interruptionEnded(mayResume: true)
        guard next != session else { return }
        session = next
        source?.play()
        published()
    }

    /// Headphones were pulled out, so the audio would come out of the speaker.
    ///
    /// `audio-playback`: playback pauses "because a book suddenly playing out loud is never
    /// what was intended", and "it does not resume by itself when they are reconnected" —
    /// which is why the cause recorded is the listener's rather than an interruption's.
    /// Reconnecting the headphones raises no interruption-ended event at all, but a route
    /// change back would, and this is what makes that harmless.
    public func routeLost() {
        guard session.isPlaying else { return }
        session = session.pausedByListener()
        source?.pause()
        published()
    }

    /// Ends the session because the audio was taken and not given back.
    ///
    /// Named apart from ``end()`` because the cause is the difference worth reading at the
    /// call site, not the state that follows — both leave a silent, controlless session, and
    /// `audio-playback` asks for both by name.
    public func lostAudio() { finish(with: session.lostAudio()) }

    /// The listener closed it, or the book ran out.
    public func end() { finish(with: session.stopped()) }

    // MARK: - What the source reports

    private func sourceMoved() {
        guard let source else { return }
        place = source.place
        book = book?.naming(title(ofPartAt: place.partIndex))
        if let sleep, case .endOfChapter = sleep.timer {
            self.sleep = SleepCountdown(timer: .endOfChapter, remaining: remaining(of: .endOfChapter))
        }
        recordReached()
        published()
    }

    /// The one way a session stops.
    ///
    /// The position first, always. `audio-playback` requires audio taken for good to end the
    /// session "and record the position", and a teardown that cleared the place before
    /// writing it would lose exactly the hour this change exists to keep.
    private func finish(with next: PlaybackSession) {
        guard session.isActive || book != nil else { return }
        recordReached()
        session = next
        source?.moved = nil
        source?.ended = nil
        source?.stop()
        source = nil
        book = nil
        parts = []
        place = .start
        sleep = nil
        unreadablePartCount = 0
        platform?.sessionEnded()
    }

    /// Says that something the lock screen shows has changed.
    ///
    /// Called at the end of every method that changes this object. A publish that lives at
    /// the call sites instead is a publish somebody forgets at one of them, and the symptom
    /// — a lock screen a few seconds behind the app — is the kind nobody reports.
    private func published() {
        platform?.published()
    }

    /// Writes down where the audio got to.
    ///
    /// On every move, not only when the session ends. A process the system reclaims gets no
    /// ending at all, and the only position that survives one is a position already written.
    private func recordReached() {
        guard let book else { return }
        onRecord?(book, place)
    }

    /// What a part is called, which is what the bar and the lock screen say.
    ///
    /// A part the container did not name falls back to its number rather than to a blank
    /// line — and never to the file name, which `design.md` records as a product decision:
    /// `01 - track.mp3` is not what a listener is in the middle of.
    private func title(ofPartAt index: Int) -> String? {
        guard parts.indices.contains(index) else { return nil }
        if let title = parts[index].title, !title.isEmpty { return title }
        return parts.count > 1 ? String(localized: "player.part.number \(index + 1)", bundle: .module) : nil
    }
}
