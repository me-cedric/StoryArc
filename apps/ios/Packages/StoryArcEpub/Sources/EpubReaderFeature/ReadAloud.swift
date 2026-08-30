internal import Foundation

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
}

/// What the lock screen says while a book is being read.
///
/// `ebook-reader` requires the publication title, and a second line is what every media
/// control has room for. The chapter is the better answer — it is what has changed since
/// the reader last looked — and the author is the fallback, because a publication that
/// declares no navigation still has one.
struct SpokenLabel: Equatable {
    let title: String
    let detail: String?

    static func of(title: String, chapter: String?, author: String?) -> SpokenLabel {
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
