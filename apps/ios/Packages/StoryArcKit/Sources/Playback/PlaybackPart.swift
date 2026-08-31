public import Foundation

/// One chapter of an audiobook, one file of a folder, or one resource of a publication
/// being read aloud.
///
/// `design.md`'s table calls this a *part*, and gives it one meaning per source: "a chapter
/// marker, or a file" for a narrated audiobook, "a resource in the publication's reading
/// order" for read-aloud. One type for both, because `audio-playback` requires the chapter
/// list to look the same either way — and requires a publication with no chapter markers to
/// list "its parts in playing order instead, rather than showing an empty list".
public struct PlaybackPart: Sendable, Equatable, Identifiable {
    /// Position in playing order, from zero.
    public let index: Int

    /// What the listener is in the middle of.
    ///
    /// `nil` when the container names nothing, which is not the same as an empty string: a
    /// part with no name of its own is presented by its number rather than by a blank line.
    /// **Naming the chapter rather than the file is a product decision**, recorded as one in
    /// `design.md`: `01 - track.mp3` is not what a listener is in the middle of.
    public let title: String?

    /// How long the part runs.
    ///
    /// `nil` for a synthesised voice, which does not know. This is the thinnest part of the
    /// abstraction and the spec is written around it — see ``PlaybackTime``.
    public let duration: TimeInterval?

    public var id: Int { index }

    public init(index: Int, title: String?, duration: TimeInterval?) {
        self.index = index
        self.title = title
        self.duration = duration
    }
}

/// Where the audio is: an offset in time inside a named part.
///
/// `reading-progress`: an audiobook's position "is an offset in time within a named part,
/// and a percentage is derived from the total duration". The part index rather than the
/// part itself, because a place has to survive being written to disk and read back beside a
/// publication whose parts are re-read from the file.
public struct PlaybackPlace: Sendable, Equatable, Codable {
    public let partIndex: Int
    public let offset: TimeInterval

    public init(partIndex: Int, offset: TimeInterval) {
        self.partIndex = partIndex
        self.offset = offset
    }

    public static let start = PlaybackPlace(partIndex: 0, offset: 0)
}

/// The position a surface states, and whether there is a total to state beside it.
///
/// **This type exists because of the one thing the two sources disagree about.**
/// `design.md`: "a narrated file knows its duration; a synthesised voice does not", and the
/// spec is written around that rather than papering over it — the compact bar states the
/// chapter rather than a countdown, and a scrub control is offered *where a duration is
/// known*. A read-aloud session shows position without a total rather than inventing one.
///
/// So the absence is a value here, not a zero and not an estimate. A surface that read
/// `total == 0` would draw a scrubber pinned at the end; one that read an estimate would
/// state a lie in seconds.
public struct PlaybackTime: Sendable, Equatable {
    /// How far into the current part.
    public let elapsed: TimeInterval
    /// The current part's length, or `nil` when the source does not know it.
    public let total: TimeInterval?

    public init(elapsed: TimeInterval, total: TimeInterval?) {
        self.elapsed = elapsed
        self.total = total
    }

    /// Whether a scrub control can be offered at all.
    ///
    /// `audio-playback`: "every control the player offers works, or is absent — none is
    /// present and refusing". A scrubber with no total to scrub through is exactly the
    /// control that would be present and refusing.
    public var isScrubbable: Bool { total != nil }

    /// How far through the part, 0…1, or `nil` when there is no total to be a fraction of.
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, elapsed / total))
    }

    public static let unknown = PlaybackTime(elapsed: 0, total: nil)
}
