public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared

internal import Persistence
internal import Playback
internal import StoryArcCore

/// What is left of read-aloud once the player owns the session.
///
/// **It used to be the session, and it is not any more.** `read-aloud-beyond-the-reader`
/// moved the voice out of `EpubReaderModel` and into a process-wide object so that closing
/// the reader would not close the book — and `audiobooks-and-playback` asks for *one* session
/// for everything that speaks. So the session, the pause table, the interruption contract,
/// the lock screen and the compact bar all moved to ``PlayerCentre``, which a narrated
/// audiobook drives through the same seam. What is left here is the half a narrator has no
/// equivalent of: the sentence drawn on a page, and the reflowable position a voice writes.
///
/// **Why it still exists at all.** ADR-0005 keeps Readium behind this package, so the
/// synthesizer, its delegate and the locators it hands back cannot be held by `Playback`.
/// ``SpokenSource`` is the adapter; this is what owns it, and what the reader talks to.
///
/// **What it owns and what it does not.** It owns the source — which owns the synthesizer and
/// the voice — the sentence cursor and the position writer: everything that has to survive a
/// screen. It does not own the highlight or the page: those need a navigator, so a reader
/// that happens to be on screen registers as ``follower`` and is let go without a word when
/// it disappears.
///
/// Android needs no equivalent type: its session already lives in a `mediaPlayback` foreground
/// service, and `ReadAloudHost` there does this routing.
@MainActor
@Observable
public final class ReadAloudCentre {

    /// The one read-aloud session there can be.
    ///
    /// `ebook-reader` allows exactly one: "two books cannot be read aloud at once". The
    /// player allows exactly one of anything — a narrated book displaces a spoken one and the
    /// reverse — so this is now the *voice's* half of a rule ``PlayerCentre`` enforces for
    /// both. A singleton because the source has to outlive every screen, which is a lifetime
    /// no screen's state has.
    public static let shared = ReadAloudCentre()

    // MARK: - What it holds

    /// The sentence being spoken. Internal, because it is Readium's.
    private(set) var spoken: Locator?

    /// The reader drawing the sentence, while one is on screen.
    ///
    /// Weak, and that is the whole of the ownership rule: the session refers to the screen,
    /// never the other way round, so a reader going away cannot take the voice with it.
    @ObservationIgnored weak var follower: EpubReaderModel?

    /// The voice, as the player sees it. `nil` when nothing is being read aloud.
    @ObservationIgnored private var source: SpokenSource?

    /// Where the voice's position goes. Copied out of the reader when the session begins, so
    /// the write does not depend on a screen that may be long gone.
    @ObservationIgnored private var position: SpokenPosition?

    /// Which publication is being read aloud, or `nil` when none is.
    ///
    /// Asked rather than stored: ``PlayerCentre`` holds the book, and a second copy here is a
    /// copy that can disagree with the bar. `nil` while a *narrated* audiobook is playing —
    /// which is the right answer to "is this publication being read aloud", and the reason
    /// this is not simply `PlayerCentre.shared.book`.
    var speaking: String? { source == nil ? nil : PlayerCentre.shared.book?.id }

    private init() {}

    // MARK: - Starting, and changing hands

    /// Takes a session over from the reader that started it.
    ///
    /// Everything the session needs afterwards is passed in here, because after this call the
    /// reader is free to disappear: the source — which holds the engine and the voice that
    /// sets its speed — where to write the position, and what to say about the book. The
    /// follower is the one thing that is allowed to go.
    ///
    /// The reader builds the source rather than handing over its parts, because the reader is
    /// what holds the opened Readium publication and the locator it is on, and neither
    /// belongs here afterwards.
    func begin(
        _ book: SpokenBook,
        speaking source: SpokenSource,
        recording position: SpokenPosition,
        drawnBy follower: EpubReaderModel
    ) {
        source.onSentence = { [weak self] locator in
            Task { await self?.reached(locator) }
        }
        source.onSilence = { [weak self] in self?.finish() }

        self.source = source
        self.position = position
        self.follower = follower

        let centre = PlayerCentre.shared
        centre.adoptSystemPlatform()
        centre.begin(book, source: source)
    }

    /// A reader has opened the book that is being spoken, and will draw its sentence.
    func adopt(_ follower: EpubReaderModel) {
        guard speaking == follower.publication.id else { return }
        self.follower = follower
    }

    /// The screen drawing the sentence has gone.
    ///
    /// The session is not touched. That is the point: `onDisappear` used to end it, and now
    /// it only says that nobody is drawing. The highlight goes with the navigator that held
    /// it, and comes back when a reader adopts the session again.
    func release(_ follower: EpubReaderModel) {
        guard self.follower === follower else { return }
        self.follower = nil
    }

    /// Draws the sentence again for a reader that has just adopted the session.
    ///
    /// `ebook-reader`: "returning resumes at the sentence being spoken then, not at the
    /// position from when they left, because the voice did not wait" — and the sentence being
    /// spoken *then* is exactly ``spoken``, which the voice has been keeping up to date with
    /// no reader on screen.
    func redrawSpokenSentence() async {
        guard let spoken else { return }
        await follower?.drawSpokenSentence(spoken)
    }

    // MARK: - What the voice reports

    /// The voice reached a sentence: draw it, move the page to it, write it down.
    private func reached(_ locator: Locator) async {
        spoken = locator
        recordReached()
        await follower?.drawSpokenSentence(locator)
    }

    /// The voice has gone quiet for good, however it ended.
    ///
    /// `ebook-reader`: at the end of the publication the voice stops, "the highlight is
    /// withdrawn, and the media controls go away" — the last two are ``PlayerCentre``'s, and
    /// this is the first. It runs for the listener's own stop and for a book that ran out
    /// alike, because both leave a page with a decoration on it and nothing speaking.
    private func finish() {
        recordReached()
        source = nil
        position = nil
        spoken = nil
        follower?.withdrawSpokenHighlight()
        follower = nil
    }

    /// Writes down where the voice got to.
    ///
    /// On every sentence, not only when the session ends. A process the system reclaims gets
    /// no ending at all, and the only position that survives one is a position already
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
