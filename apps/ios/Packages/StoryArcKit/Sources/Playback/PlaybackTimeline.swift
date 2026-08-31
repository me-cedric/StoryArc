public import Foundation

/// The arithmetic a narrated source does over its parts.
///
/// **An engine knows one number: how far into the current *file* it is.** Everything a
/// listener sees — which chapter, how far into it, where a skip lands, which file to load
/// next — is arithmetic over the parts, and arithmetic is the half that can be wrong in a
/// way no simulator would show. A chapter boundary off by one, a skip that stops dead at
/// the end of a chapter, a place that falls off the list a fraction past the last marker:
/// all three look like nothing at all until somebody is listening.
///
/// So it is a value, asserted on the host, and ``NarratedSource`` is the thin part that
/// talks to `AVPlayer`.
///
/// The two shapes it serves are genuinely different. A chaptered M4B is several parts
/// inside **one** file at increasing offsets; a folder is one part per file, each starting
/// at zero. Nothing below branches on which — a part carries its own file and its own start,
/// and that is enough for both.
public struct PlaybackTimeline: Sendable, Equatable {
    public let parts: [AudiobookPart]

    public init(parts: [AudiobookPart]) {
        self.parts = parts
    }

    /// What the player draws: the same parts with the file dropped.
    ///
    /// A surface has no business knowing which file a chapter is in, and `audio-playback`
    /// requires the chapter list to look the same whether the parts came from one container
    /// or from ten.
    public var playbackParts: [PlaybackPart] {
        parts.enumerated().map { index, part in
            PlaybackPart(index: index, title: part.title, duration: part.duration)
        }
    }

    /// Which part a file's clock is in, and how far into it.
    ///
    /// - Returns: `nil` when the file is not one of this book's, which is how a source
    ///   ignores a stale time observation from an item it has already swapped out.
    public func place(atFileTime time: TimeInterval, in url: URL) -> PlaybackPlace? {
        let candidates = parts.indices.filter { parts[$0].url == url }
        guard let first = candidates.first else { return nil }

        // The *last* part that starts at or before this time. Walking forward rather than
        // testing each part's range means a file that runs a fraction past its final
        // chapter marker still belongs to the final chapter, instead of belonging to
        // nothing and blanking the chapter line at the end of every book.
        var found = first
        for index in candidates where parts[index].start <= time {
            found = index
        }
        return PlaybackPlace(partIndex: found, offset: max(0, time - parts[found].start))
    }

    /// Which file to play, and where in it, to reach a part.
    public func seek(toPart index: Int, offset: TimeInterval) -> (url: URL, fileTime: TimeInterval)? {
        guard parts.indices.contains(index) else { return nil }
        let part = parts[index]
        return (part.url, part.start + max(0, offset))
    }

    /// Where a skip lands.
    ///
    /// `audio-playback`: "skipping past the start or the end of a chapter continues into the
    /// neighbouring one rather than stopping at the boundary". Which is why this works in
    /// whole-book time and converts back, rather than clamping inside the current part —
    /// clamping is exactly the boundary stop the spec forbids.
    ///
    /// The two ends of the book are still ends: nothing before the start, and nothing past
    /// the last part. A listener holding skip-back at the beginning sits at zero rather than
    /// being refused or wrapped around.
    public func skip(
        _ direction: SkipDirection,
        by interval: TimeInterval,
        from place: PlaybackPlace
    ) -> PlaybackPlace? {
        guard let elapsed = bookTime(of: place) else { return nil }
        let moved = direction == .back ? elapsed - interval : elapsed + interval
        return self.place(atBookTime: moved)
    }

    /// How far into the whole book a place is, or `nil` when a part before it has no length.
    func bookTime(of place: PlaybackPlace) -> TimeInterval? {
        guard parts.indices.contains(place.partIndex) else { return nil }
        var elapsed: TimeInterval = 0
        for index in 0..<place.partIndex {
            guard let duration = parts[index].duration else { return nil }
            elapsed += duration
        }
        return elapsed + place.offset
    }

    /// The place a whole-book time names, clamped to the book's two ends.
    func place(atBookTime time: TimeInterval) -> PlaybackPlace? {
        guard !parts.isEmpty else { return nil }
        guard time > 0 else { return .start }

        var remaining = time
        for index in parts.indices {
            guard let duration = parts[index].duration else {
                // Nothing after this can be measured, so this is as far as the arithmetic
                // honestly reaches.
                return PlaybackPlace(partIndex: index, offset: remaining)
            }
            if remaining < duration {
                return PlaybackPlace(partIndex: index, offset: remaining)
            }
            remaining -= duration
        }
        // Past the end of the book: the end of the last part, which is where a player that
        // ran out would be sitting anyway.
        let last = parts.count - 1
        return PlaybackPlace(partIndex: last, offset: parts[last].duration ?? 0)
    }
}
