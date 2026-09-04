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
    /// Read through the two questions below: what silenced the audio is this type's business,
    /// and a surface needs only "is there a session" and "is it playing". Exposing the cause
    /// would invite a view to decide what a pause means, which is the one decision
    /// ``PlaybackSession`` exists to keep in one place.
    ///
    /// `internal(set)` rather than `private(set)` only because the sleep timer lives in a
    /// second file — `PlayerSleep.swift`, as the position lives in `PlayerPosition.swift`.
    /// Nothing outside this module may set it, and nothing inside it does but those two.
    public internal(set) var session = PlaybackSession()

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

    /// The sleep timer, while one is set. Everything that moves it is in `PlayerSleep.swift`.
    public internal(set) var sleep: SleepCountdown?

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

    /// Whether the source has reached the end of the book.
    ///
    /// Kept apart from ``session`` because it is a different question: a stopped session is a
    /// session with no audio, and this says *why*. `reading-progress` needs the difference —
    /// a listener who stopped half way has not finished the publication and a book that ran
    /// out has. Cleared by ``begin(_:source:)``, so a second book cannot inherit it.
    public private(set) var hasReachedTheEnd = false

    // MARK: - What the app wires in

    /// Where a session's position goes.
    ///
    /// A closure rather than a store, because `Playback` has no business knowing about
    /// SwiftData: `reading-progress` owns the record and the app layer owns the wiring. It
    /// is called on every part change, whenever a session ends, and — the case that matters
    /// — *before* a second book displaces the first.
    ///
    /// It hands over a finished ``ReachedListening`` rather than a ``PlaybackPlace``: the
    /// part count, the current part's length and whether the book ran out are all this
    /// object's to know, and an app-layer closure asking for them one at a time is an
    /// app-layer closure that can get the finished rule wrong.
    public var onRecord: (@MainActor (ReachedListening) -> Void)?

    /// The speed to start a publication at.
    ///
    /// `audio-playback`: speed "is remembered for that publication and offered as the default
    /// for others in the same series". The remembering is the app's; the asking is here.
    public var onRecallSpeed: (@MainActor (Publication) -> PlaybackSpeed?)?

    /// A speed the listener chose, to be remembered against this publication.
    public var onRememberSpeed: (@MainActor (Publication, PlaybackSpeed) -> Void)?

    /// Told when the listener changes how far a skip moves, so it can be kept.
    public var onRememberSkip: (@MainActor (SkipIntervals) -> Void)?

    /// The artwork the system's own media controls show, as PNG bytes.
    ///
    /// `audio-playback`: a publication with no cover gets "the same coverless treatment every
    /// other surface draws — the title set as artwork", **and** "the system's own media controls
    /// get that same artwork, because a lock screen showing a headphones symbol is the one place
    /// a listener looks for an hour".
    ///
    /// A closure and bytes rather than an image, because drawing a title into a square needs
    /// SwiftUI and this target has none: `Formats` depends on it for `AudiobookPart`, and a
    /// parser has no business linking a design system. `PlayerArtworkImage` in `PlayerFeature`
    /// owns the treatment and renders it from the very view the player draws; ``NowPlaying``
    /// turns the bytes into an `MPMediaItemArtwork` and caches them per book.
    ///
    /// `nil`, or a `nil` return, publishes *no* artwork — which is what the lock screen showed
    /// before this existed, so nothing is worse for a session the app cannot draw a cover for.
    public var onArtwork: (@MainActor (SpokenBook) -> Data?)?

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
    /// See ``PlayerCentre/adoptSystemPlatform()``, in `PlaybackPlatform.swift`.
    @ObservationIgnored public var platform: (any PlaybackPlatform)?

    /// The engine, whichever kind it is. Internal rather than private for the reason
    /// ``session`` is: `PlayerSleep.swift` has to fade it and stop it.
    @ObservationIgnored internal var source: (any PlaybackSource)?

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
        // Cleared here rather than in `finish`, which runs *before* this on a displacement and
        // has to leave the flag standing long enough for the outgoing book's record to carry
        // it. A listener who finished one book and started another would otherwise have the
        // second marked finished at its first tick.
        hasReachedTheEnd = false
        unreadablePartCount = source.unreadablePartCount
        self.book = book.naming(title(ofPartAt: place.partIndex))
        speed = onRecallSpeed?(book.publication) ?? .normal

        source.moved = { [weak self] in self?.sourceMoved() }
        // The book ran out. The flag before the teardown, because `end()` writes the position
        // on its way out and `reading-progress` asks that record whether the publication is
        // finished.
        source.ended = { [weak self] in
            self?.hasReachedTheEnd = true
            self?.end()
        }
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

    /// Pause, from a control that means *pause* rather than *pause or play*.
    ///
    /// Apart from ``toggle()`` because the lock screen, a paired watch and a car send a
    /// `pauseCommand` and not a toggle, and the difference matters in exactly one state: a
    /// session the platform has already silenced. A toggle there means *play*, and the
    /// listener pressing a pause button means the opposite — so the two cannot be the same
    /// call. `MPRemoteCommandCenter`'s pause target used to refuse in that state, which left
    /// the pause recorded as the interruption's and the book resuming when the call ended.
    /// Android's session pause has always taken this path; see `PlaybackSession.pausedByListener`.
    public func pause() {
        guard session.isActive, let source else { return }
        session = session.pausedByListener()
        source.pause()
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
        // End of chapter is a place, so it moves when the audio does — including by a skip
        // the listener made between two ticks. The volume is left to the tick, which is at
        // most half a second away.
        if let sleep, sleep.timer == .endOfChapter {
            self.sleep = sleep.ticked(by: 0, playing: time)
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
    ///
    /// Internal rather than private only because the sleep timer's own methods are in a second
    /// file and each of them ends here too.
    internal func published() {
        platform?.published()
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
