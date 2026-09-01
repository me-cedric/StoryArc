public import Foundation

public import Playback

/// What a skip control states.
///
/// `audio-playback`: "the interval is stated on the control itself". A synthesised voice has
/// no seconds to state, and `ebook-reader` asks its controls for sentence skip by name — so
/// two cases, and the surface never asks which *source* is playing to tell them apart.
public enum SkipLabel: Equatable, Sendable {
    /// The configured interval, already formatted: "15 seconds", "1 minute".
    case time(String)
    case sentence
}

/// What the line under the chapter states.
///
/// `design.md`: a source with no duration "shows position without a total rather than
/// inventing one". So there is no case carrying a zero total — the absence is a different
/// case, and a surface cannot accidentally render `0:00 / 0:00`.
public enum PositionLabel: Equatable, Sendable {
    /// Elapsed and total, both formatted.
    case time(elapsed: String, total: String)
    /// Which part, out of how many, for a source that knows no duration.
    case part(index: Int, of: Int)
    /// A book of one part with no duration: there is no position worth stating.
    case none
}

/// What a part is called in the chapter list.
///
/// `audio-playback`: a publication with no chapter markers "lists its parts in playing order
/// instead, rather than showing an empty list" — so an unnamed part is *numbered*, never
/// blank, and never the file's name.
public enum ChapterLabel: Equatable, Sendable {
    case title(String)
    /// One-based, for a part the container did not name.
    case number(Int)
}

/// What the player states, decided here and spoken by the surfaces.
///
/// **A value with tests rather than string interpolation inside a view body**, because every
/// one of these is a requirement rather than a formatting preference — the interval a skip
/// control states, the position a screen reader hears, the number of a part the container
/// did not name — and a requirement stated inside a `Text` is a requirement nothing checks.
///
/// It returns *decisions* and formatted numbers, never translated prose. Two reasons, and
/// both are load-bearing:
///
/// - `scripts/ios-strings.mjs` proves every key resolves in all four languages by reading
///   `Text("…")` and `String(localized: "…")` out of the source. A sentence assembled here
///   would be a sentence that gate cannot see.
/// - `swift build` copies an `.xcstrings` without compiling it, so `String(localized:)`
///   answers with the key itself on the host — measured, not assumed. A host test that
///   asserted English prose would be asserting a lookup that cannot work where it runs.
///
/// **Two forms of every time, and the difference is the point.** `0:09` is right on the face
/// of a player and wrong in a screen reader, which reads it "zero colon zero nine".
/// `audio-playback` asks for the scrub control's position "stated in time, not as a
/// percentage", and that is what ``spokenTime(_:)`` is for.
public enum PlayerLabels {

    // MARK: - Time

    /// A position as a player writes it: `9:59`, or `1:02:30` past the hour.
    ///
    /// Built by hand rather than by a formatter, because this one is not prose: it is the
    /// digits every media player in the world shows, and a locale that reordered them would
    /// be one where a listener could not read their own book's clock.
    public static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let whole = Int(seconds.rounded(.down))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// A position as a screen reader should hear it: "1 minute, 10 seconds".
    ///
    /// `Duration`'s own units format, so the words and their order are the platform's in
    /// every language rather than four more strings this project would have to keep in step.
    public static func spokenTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return format(.seconds(0)) }
        return format(.seconds(seconds.rounded()))
    }

    private static func format(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    // MARK: - The controls

    /// What a skip control states on its face and to a screen reader.
    ///
    /// The *configured* interval, not the default: `audio-playback` requires the interval to
    /// be one "the listener can configure", and a control that stated the default while
    /// moving by something else would be worse than one that stated nothing.
    public static func skip(
        _ direction: SkipDirection,
        unit: SkipUnit,
        intervals: SkipIntervals
    ) -> SkipLabel {
        switch unit {
        case .sentence: .sentence
        case .time: .time(format(.seconds(intervals.interval(direction).rounded())))
        }
    }

    // MARK: - Where the audio is

    /// The line under the chapter.
    ///
    /// A book of one part with no duration states nothing: "Part 1 of 1" is a number a
    /// listener cannot use.
    public static func position(part index: Int, of count: Int, time: PlaybackTime) -> PositionLabel {
        if let total = time.total {
            return .time(elapsed: self.time(time.elapsed), total: self.time(total))
        }
        guard count > 1 else { return .none }
        return .part(index: index + 1, of: count)
    }

    // MARK: - The chapter list

    /// What a part is called in the list.
    public static func chapter(_ part: PlaybackPart) -> ChapterLabel {
        if let title = part.title, !title.isEmpty { return .title(title) }
        return .number(part.index + 1)
    }

    /// How long a part runs, or `nil` when nothing knows.
    ///
    /// `nil` rather than `0:00`: a chapter list showing every chapter as zero long is worse
    /// than one showing no lengths at all, because the first states something false.
    public static func length(of part: PlaybackPart) -> String? {
        part.duration.map(time)
    }
}
