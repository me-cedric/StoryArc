public import Foundation

public import StoryArcCore

// What reading aloud is, with no engine in it.
//
// `ebook-reader` asks for speech that starts at the reader's position, follows the page,
// and survives the app going to the background. Almost all of that is platform work —
// an engine, an audio session, a now-playing centre — but one part is a decision, and it
// is the part that goes wrong: what a pause *means*.
//
// A reader who pressed pause and a phone call that took the audio away both leave the
// voice silent, and they must not end the same way. When the call ends the book should
// carry on; when the reader pressed pause it must not, or a book starts talking again on
// its own the moment an unrelated notification finishes.
//
// So the cause of the pause is carried with the pause, and the transitions live here
// where they can be asserted without a speaker. Android pins the same table in
// `ReadAloud.kt`.

/// Whether the voice is running, stopped, or holding.
enum ReadAloudState: Equatable {
    case idle
    case speaking
    case paused
}

/// Who silenced it, which decides whether the end of an interruption starts it again.
enum PauseCause: Equatable {
    case reader
    case interruption
}

/// The state of reading aloud, and every way it can change.
///
/// A value rather than a class: each event returns the session that follows it, so a
/// wrong transition is something a test can compare rather than a field somebody forgot
/// to clear.
struct ReadAloudSession: Equatable {
    private(set) var state: ReadAloudState
    /// `nil` unless ``state`` is ``ReadAloudState/paused``.
    private(set) var pausedBy: PauseCause?

    init(state: ReadAloudState = .idle, pausedBy: PauseCause? = nil) {
        self.state = state
        self.pausedBy = pausedBy
    }

    /// Whether a sentence is being spoken right now.
    var isSpeaking: Bool { state == .speaking }

    /// Whether the transport controls belong on screen at all.
    ///
    /// Paused counts: a reader who paused still needs the play button, and skipping a
    /// sentence while paused is how somebody gets past a sentence they do not want read.
    var isActive: Bool { state != .idle }

    /// Starting, or restarting from a new position.
    func started() -> ReadAloudSession { ReadAloudSession(state: .speaking) }

    /// The reader pressed pause. Nothing but the reader starts this again.
    func pausedByReader() -> ReadAloudSession {
        isSpeaking ? ReadAloudSession(state: .paused, pausedBy: .reader) : self
    }

    /// Something else took the audio: a call, another app, a spoken direction.
    ///
    /// A pause the reader already made is left exactly as it was — otherwise a
    /// notification arriving during a deliberate pause would convert it into one that
    /// resumes on its own.
    func interrupted() -> ReadAloudSession {
        isSpeaking ? ReadAloudSession(state: .paused, pausedBy: .interruption) : self
    }

    /// The reader pressed play.
    func resumed() -> ReadAloudSession {
        state == .paused ? ReadAloudSession(state: .speaking) : self
    }

    /// The interruption is over.
    ///
    /// - Parameter mayResume: the platform's own answer — iOS puts it in the
    ///   interruption notification's options, Android in whether the focus came back at
    ///   all. Speech resumes only when the platform says so *and* the pause was the
    ///   interruption's.
    func interruptionEnded(mayResume: Bool) -> ReadAloudSession {
        (mayResume && pausedBy == .interruption) ? resumed() : self
    }

    /// The audio is gone for good — another app took it and kept it.
    ///
    /// Stopped rather than paused: there is nothing to wait for, and a session that sat
    /// paused for ever would hold an audio session open for a book nobody is hearing.
    func lostAudio() -> ReadAloudSession { ReadAloudSession() }

    /// The reader closed it, or the book ran out of words.
    func stopped() -> ReadAloudSession { ReadAloudSession() }

    /// What the end of an interruption means for this session.
    ///
    /// Three answers, not two, and the missing third is the defect this fixes: iOS handled
    /// the interruption beginning and ending, and an ending the platform would not resume
    /// matched neither branch — so the session sat paused for ever, with no position
    /// written and nothing telling the listener. `ebook-reader` names the case: "audio
    /// taken for good stops the session rather than leaving it paused for ever".
    ///
    /// - Parameter mayResume: the platform's own answer — iOS reads it from the
    ///   interruption notification's `shouldResume`, Android from whether the focus came
    ///   back at all rather than being taken outright.
    func endingInterruption(mayResume: Bool) -> InterruptionOutcome {
        // Taken for good, and it ends the session whoever silenced it: a session left
        // paused with nothing able to start it is exactly what the spec forbids. That is
        // not the pause being *undone* — the other clause forbids resuming a pause the
        // reader made, and this never resumes one.
        guard mayResume else { return isActive ? .lost : .nothing }
        return pausedBy == .interruption ? .resume : .nothing
    }
}

/// What the end of an interruption does to a session.
///
/// A value rather than a branch inside each platform's audio callback, because the two
/// callbacks look nothing alike — one notification with an options bitmask on iOS, a stream
/// of focus changes on Android — and the decision underneath them is the same one. Android
/// pins these three in `ReadAloud.kt`.
enum InterruptionOutcome: Equatable {
    /// Nothing to do: the voice was not the interruption's to give back.
    case nothing
    /// The audio came back and the pause was the interruption's, so the voice carries on.
    case resume
    /// The audio is gone for good. The session ends, and its position is written first.
    case lost
}

/// The colour the sentence being spoken is drawn in.
///
/// Deliberately not one of the five a reader can highlight with, and deliberately not the
/// accent: a mark the reader made is something they can come back to, and the voice's
/// place is not. A neutral at the same weight reads as "the voice is here" without
/// offering itself as a mark — and it stays legible under every reading theme, which a
/// hue would not.
///
/// Android draws the same colour from the same three numbers in `ReadAloud.kt`.
enum SpokenHighlight {
    static let red = 0.55
    static let green = 0.55
    static let blue = 0.58
}

/// What the lock screen says while a book is being read.
///
/// `ebook-reader` requires the publication title, and a second line is what every media
/// control has room for. The chapter is the better answer — it is what has changed since
/// the reader last looked — and the author is the fallback, because a publication that
/// declares no navigation still has one.
///
/// Public because the transport outside the reader says the same two things the lock
/// screen does, and `ebook-reader` requires them to match: it "names the publication being
/// spoken and the chapter, matching what the platform's own media controls show".
public struct SpokenLabel: Equatable, Sendable {
    public let title: String
    public let detail: String?

    public static func of(title: String, chapter: String?, author: String?) -> SpokenLabel {
        SpokenLabel(
            title: title,
            detail: chapter.flatMap(nonEmpty) ?? author.flatMap(nonEmpty)
        )
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A book being read aloud: what to say about it, and the way back to it.
///
/// Held by ``ReadAloudCentre`` rather than by a screen, because the session outlives every
/// screen and the transport that offers the way back is drawn by something above them all.
/// The URL travels with the publication for exactly that reason: whoever offers "back to
/// the book" has to open the same bytes without asking a reader that has gone.
public struct SpokenBook: Equatable, Sendable, Identifiable {
    public let publication: Publication
    /// Where the bytes are, so the way back opens the book rather than a search for it.
    public let url: URL
    /// The chapter the voice is in, which is the line both transports have room for.
    public internal(set) var chapter: String?

    public var id: String { publication.id }

    /// What the transport and the media controls both say.
    public var label: SpokenLabel {
        SpokenLabel.of(
            title: publication.displayTitle,
            chapter: chapter,
            author: publication.authors.first
        )
    }

    public init(publication: Publication, url: URL, chapter: String? = nil) {
        self.publication = publication
        self.url = url
        self.chapter = chapter
    }
}

/// Where the voice got to, in the form the progress store takes.
///
/// The handoff, as a value. The reader used to be the only thing that wrote a position: it
/// wrote on every navigator move, and the page followed the voice, so the two agreed. A
/// session that outlives its screen has no navigator to move, so the voice writes for
/// itself — and what it writes is the decision worth asserting, which is why it is a value
/// rather than a call into a database.
///
/// `ebook-reader`: the recorded position "is where the voice got to, not where the reading
/// stopped … whether the session ended with the publication open or continued after it was
/// closed". Android pins the same shape in `ReadAloud.kt`.
struct ReachedPosition: Equatable, Sendable {
    /// The sentence being spoken, as Readium's own opaque locator JSON.
    ///
    /// Not a page number: `ebook-reader` requires the position to survive a type-size
    /// change, and a reflowable page number cannot.
    let locator: String
    /// How far through the whole publication, 0…1.
    let progression: Double

    /// Whether there is anything worth writing down.
    ///
    /// A sentence Readium could not turn into a locator is a sentence nothing can resume
    /// from, and writing an empty one over a good position is how an hour is lost.
    var isRecordable: Bool { !locator.isEmpty }

    /// The record `reading-progress` stores.
    func record(for identity: PublicationIdentity, at moment: Date) -> ReadingProgress {
        ReadingProgress(
            identity: identity,
            position: .reflowable(progression: progression, locator: locator),
            // The reader's own rule: a reflowable book is finished at the end of its
            // content rather than at a page number.
            isFinished: progression >= Self.finished,
            updatedAt: moment
        )
    }

    /// Close enough to the end of the content to count as the end of the book.
    static let finished = 0.999
}

/// What opening a publication does to a voice that is already speaking.
///
/// One session at a time. `ebook-reader`: "the session ends at a sentence boundary and the
/// position it reached is recorded before the new publication opens" — two books cannot be
/// read aloud at once, and switching silently would lose a listener's place.
///
/// The same question answers what a reader coming *back* to the book being spoken does: it
/// picks the voice up rather than starting another. Both live here as a value so they can
/// be asserted without a speech engine, in the way the pause table already is. Android
/// pins the same three in `ReadAloud.kt`.
enum SessionHandover: Equatable {
    /// Nothing is speaking. The reader opens silent, as it always did.
    case none
    /// The book being opened is the book being spoken, so the reader observes the session
    /// rather than starting another.
    case adopt
    /// A different book. The voice ends at the sentence it reached and that position is
    /// written down before the new publication draws a word.
    case displace

    /// - Parameter spoken: the identity of the book being spoken, or `nil` for silence.
    static func opening(_ publication: String, whileSpeaking spoken: String?) -> SessionHandover {
        guard let spoken else { return .none }
        return publication == spoken ? .adopt : .displace
    }
}
