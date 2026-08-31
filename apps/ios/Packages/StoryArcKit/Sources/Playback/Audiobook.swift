public import Foundation

/// One part of an audiobook: a chapter marker inside a file, or a whole file of a folder.
///
/// `design.md`'s table calls both a *part*, and `publication-formats` requires them to
/// behave the same way — "its parts — the files, or the whole of a single file — stand in
/// for chapters". So one type, carrying where the audio is and where inside it the part
/// begins.
///
/// **Here rather than in `Formats`, and the precedent is `PublicationFormat`'s.** That enum
/// moved to `StoryArcCore` because the library sorts, filters and explains by format and
/// none of that should require the parser. The same holds one layer along: the player draws
/// parts, seeks between them and names them, and none of that should require a ZIP reader.
/// `Formats` produces these; it does not own them.
public struct AudiobookPart: Sendable, Equatable {
    /// The file this part is in. The same URL for every chapter of an M4B; a different one
    /// for every part of a folder.
    public let url: URL

    /// What the container calls it, or `nil` when it names nothing.
    ///
    /// **Never the file name.** `design.md` records that as a product decision:
    /// `01 - track.mp3` is not what a listener is in the middle of. A part with no name is
    /// numbered by ``PlayerCentre``, which is the one place that decision lives.
    public let title: String?

    /// Where this part starts inside ``url``. Zero for a whole file.
    public let start: TimeInterval

    /// How long it runs, when the container says.
    public let duration: TimeInterval?

    public init(url: URL, title: String?, start: TimeInterval, duration: TimeInterval?) {
        self.url = url
        self.title = title
        self.start = start
        self.duration = duration
    }

    /// Where this part ends inside its file, when its length is known.
    public var end: TimeInterval? { duration.map { start + $0 } }
}

/// An audiobook as the format layer sees it: parts in playing order, and what was lost.
public struct Audiobook: Sendable, Equatable {
    public let parts: [AudiobookPart]

    /// How many entries looked like parts and could not be read.
    ///
    /// `publication-formats`: a damaged audiobook "plays what it can and states how much it
    /// could not … the count is stated in the player's own controls rather than
    /// interrupting playback" — the same rule that opens a comic missing pages.
    public let unreadablePartCount: Int

    public init(parts: [AudiobookPart], unreadablePartCount: Int) {
        self.parts = parts
        self.unreadablePartCount = unreadablePartCount
    }

    /// The whole book's length, or `nil` when any part's is unknown.
    public var duration: TimeInterval? {
        let durations = parts.compactMap(\.duration)
        guard durations.count == parts.count, !parts.isEmpty else { return nil }
        return durations.reduce(0, +)
    }
}
