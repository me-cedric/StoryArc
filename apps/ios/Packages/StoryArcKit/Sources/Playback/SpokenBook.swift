public import Foundation

public import StoryArcCore

/// What the lock screen says while a book is playing.
///
/// `audio-playback` requires the system's own media controls to show "the publication, the
/// chapter", and a second line is what every media control has room for. The chapter is the
/// better answer — it is what has changed since the listener last looked — and the author is
/// the fallback, because a publication that declares no navigation still has one.
///
/// The compact bar says the same two things the lock screen does, and the spec requires
/// them to match, so both read this one value.
public struct SpokenLabel: Equatable, Sendable {
    public let title: String
    public let detail: String?

    public static func of(title: String, chapter: String?, author: String?) -> SpokenLabel {
        SpokenLabel(
            title: title,
            detail: chapter.flatMap(nonEmpty) ?? author.flatMap(nonEmpty)
        )
    }

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A book being played: what to say about it, and the way back to it.
///
/// Held by ``PlayerCentre`` rather than by a screen, because the session outlives every
/// screen and the compact bar that offers the way back is drawn by something above them all.
/// The URL travels with the publication for exactly that reason: whoever offers "back to the
/// book" has to open the same bytes without asking a reader that has gone.
///
/// It says nothing about *which* kind of audio it is. `audio-playback`: "the synthesised
/// voice is named once on the publication's own page rather than in the player" — so the
/// player's own model has no field for it, which is the strongest form of that promise.
public struct SpokenBook: Equatable, Sendable, Identifiable {
    public let publication: Publication
    /// Where the bytes are, so the way back opens the book rather than a search for it.
    public let url: URL
    /// The part the audio is in, which is the line both the bar and the lock screen have
    /// room for. Set through ``naming(_:)`` as the audio moves.
    public private(set) var chapter: String?

    public var id: String { publication.id }

    /// What the compact bar and the media controls both say.
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

    /// The same book, in a different part.
    ///
    /// A returned copy rather than a settable property: the chapter is the *only* thing
    /// about a playing book that changes, and every other field would be wrong to change
    /// after the session began. Naming the one mutation makes that structural.
    public func naming(_ chapter: String?) -> SpokenBook {
        SpokenBook(publication: publication, url: url, chapter: chapter)
    }
}

/// What a session has to write down.
///
/// **A value rather than three arguments, and the position rather than the place.**
/// `reading-progress` gives an audiobook one position and one finished flag, and both are
/// decisions only ``PlayerCentre`` can make: it holds the parts, so it knows how many there
/// are and how long the current one is, and it is what the source tells when the book has run
/// out. A closure in the app layer given a bare ``PlaybackPlace`` would have had to ask for
/// each of those separately, and would have got the finished rule wrong — see ``isFinished``.
public struct ReachedListening: Sendable, Equatable {
    public let book: SpokenBook

    /// Where the listener got to, in the currency the store and the merge deal in.
    public let position: ReadingPosition

    /// Whether the publication is finished.
    ///
    /// `reading-progress`: "the publication is marked finished by the same rule that marks a
    /// comic finished on its last page". A comic knows it is on its last page; an audiobook
    /// knows its source ran out, which is the same fact and the only **exact** one available.
    /// A threshold on ``position``'s fraction was the obvious alternative and it is wrong: the
    /// clock ticks four times a second, so the last place reported before the end of the
    /// corpus's six-second fixture is a fraction of about 0.96 — a book that played to its end
    /// and was never marked finished.
    public let isFinished: Bool

    public init(book: SpokenBook, position: ReadingPosition, isFinished: Bool) {
        self.book = book
        self.position = position
        self.isFinished = isFinished
    }
}

/// Where the compact bar's own row takes a listener.
///
/// **Two clauses of `audio-playback` land on the same row and they do not always agree.**
/// The bar offers "a way to open the full player", and separately "the way back to where the
/// audio is reading is one action from the compact bar". For a narrated audiobook those are
/// one place: nothing took the listener away from a screen, and the player *is* where the
/// audio is. For a publication being read aloud they are two, and `ebook-reader` settles
/// which the row owes — "the compact bar is how the reader gets back to it", returning "at
/// the sentence being spoken then". ``PlayerDock`` draws a separate control for the player
/// in that case, so neither clause is traded away.
///
/// **What decides it is the file.** `audio-playback` says a listener's source is "a fact
/// about the file, stated once where the publication is described" — so this asks
/// `publication.format`, and never which ``PlaybackSource`` is behind the sound. A narrated
/// audiobook read by a future engine still has no reader to go back to, and an EPUB spoken
/// by any engine still has one.
public enum PlayerWayBack: Equatable, Sendable {
    /// There is no screen behind the audio: the player is the destination.
    case fullPlayer
    /// The publication itself — reopened at the sentence the voice is on.
    case publication
}

/// What the compact bar shows — and whether there is one at all.
///
/// **`nil` is the requirement, not a convenience.** `audio-playback`: when no session is
/// active "the compact bar is absent rather than present and empty, and the space it
/// occupied returns to the content". Absent is not hidden, not disabled and not empty: there
/// is no value, so the shell has nothing to put in its accessory slot and the slot does not
/// open. Holding that as a value rather than as an `if` inside a view body is what lets a
/// test assert it — the rule is the one a later layout change breaks most easily, and a tab
/// bar cannot be unit-tested.
///
/// Its words come from ``SpokenBook/label`` — the same value the lock screen is given —
/// because the spec requires the two to match.
public struct CompactPlayer: Equatable, Sendable {
    /// The book being played, carried whole because the way back has to open the same bytes
    /// without asking a screen that has gone. See ``SpokenBook/url``.
    public let book: SpokenBook
    /// Whether audio is coming out, which is the only question the play button asks.
    public let isPlaying: Bool

    /// What the bar says, which is what the media controls say.
    public var label: SpokenLabel { book.label }

    /// Where the bar's own row goes. See ``PlayerWayBack``.
    public var wayBack: PlayerWayBack {
        book.publication.format.isAudio ? .fullPlayer : .publication
    }

    /// - Returns: `nil` when there is no session to control — including a session that has
    ///   just ended, whether the listener ended it, the audio was taken for good, or the
    ///   book ran out. All three leave an inactive session, and all three are required to
    ///   withdraw the bar.
    public static func of(_ session: PlaybackSession, playing book: SpokenBook?) -> CompactPlayer? {
        guard session.isActive, let book else { return nil }
        return CompactPlayer(book: book, isPlaying: session.isPlaying)
    }
}
