public import Foundation

/// Where someone stopped reading.
///
/// A paged publication stores a page index. A reflowable one stores a fraction
/// through the content plus an opaque locator, because a reflowable page number
/// is a function of the reader's typography and is not stable across devices —
/// ADR-0006.
public enum ReadingPosition: Sendable, Equatable, Codable {
    case page(index: Int, of: Int)
    case reflowable(progression: Double, locator: String)

    /// Where a listener stopped: an offset in time inside one part of a publication.
    ///
    /// `reading-progress`: "it is an offset in time within a named part". The same case
    /// carries a narrated audiobook and a publication being read aloud, because
    /// `audio-playback` gives them one player and this gives them one position — "the app
    /// does not keep a separate listening position, so returning never offers a choice of
    /// two places".
    ///
    /// **Four decisions inside this signature.**
    ///
    /// `part` is an index and the part's *name* is not stored. A chapter title belongs to the
    /// file, and a position carrying a stale copy of one would disagree with the book after a
    /// re-download.
    ///
    /// `offset` is seconds into that part, not into the whole publication. A folder
    /// audiobook's parts can be re-ordered or replaced one at a time, and a whole-publication
    /// offset silently moves when an earlier part changes length.
    ///
    /// **`of` is optional, and that is the load-bearing part.** A read-aloud session has no
    /// true duration — `PlaybackTime.total` is nullable on both platforms precisely so an
    /// estimate can never be presented as exact — so a position taken from one has no total to
    /// divide by, and ``fraction`` answers with the part instead of a guess.
    ///
    /// `partCount` is here and **not in `design.md`'s signature**, which names three fields
    /// and then asks ``fraction`` for "the part index over the part count". That count is not
    /// derivable from the other three, so the case cannot answer without it. ``page`` carries
    /// its total for the same reason and in the same shape. Android's `Listening` has the
    /// identical four fields, for the identical reason.
    case listening(part: Int, partCount: Int, offset: TimeInterval, of: TimeInterval?)

    /// Normalised 0…1, so two positions can be compared regardless of kind.
    public var fraction: Double {
        switch self {
        case let .page(index, total):
            guard total > 1 else { return total == 1 && index >= 0 ? 1 : 0 }
            return min(1, max(0, Double(index) / Double(total - 1)))
        case let .reflowable(progression, _):
            return min(1, max(0, progression))
        case let .listening(part, partCount, offset, total):
            // The part, plus how far into it the listener is when anything knows. With no
            // duration the second term is zero rather than an estimate: a fraction refined by
            // a guess is a guess presented as a measurement, and the whole reason `of` is
            // optional is that this app does not do that.
            guard partCount > 0 else { return 0 }
            let within = total.flatMap { $0 > 0 ? min(1, max(0, offset / $0)) : nil } ?? 0
            return min(1, max(0, (Double(part) + within) / Double(partCount)))
        }
    }

    /// Whether this describes the same point in a publication as another.
    ///
    /// By ``fraction`` rather than by case, because that is the currency the whole merge
    /// deals in — and because a store is entitled to keep a synced position as the one
    /// number that survives a change of typography. Android's does exactly that, and while
    /// this was case equality, a page position could never equal the one it had just been
    /// stored from, so ADR-0006's first row — remote ahead, local untouched, adopt quietly —
    /// was unreachable there. Android's `matches` is the same line.
    public func matches(_ other: ReadingPosition) -> Bool { fraction == other.fraction }
}

public struct ReadingProgress: Sendable, Equatable, Codable {
    public let identity: PublicationIdentity
    public var position: ReadingPosition
    public var isFinished: Bool

    /// When it was finished, which `reading-progress` asks for by name: a publication is
    /// "recorded finished with a completion timestamp".
    ///
    /// Separate from ``updatedAt`` because they answer different questions. `updatedAt`
    /// moves every fifteen seconds of reading; this moves once, and only when the finished
    /// flag turns on. Reopening a finished publication writes a new position — and must not
    /// rewrite when it was finished.
    public var finishedAt: Date?

    public var updatedAt: Date

    /// The last position successfully exchanged with the source. Comparing
    /// against it is how the merge tells "changed since last sync" from
    /// "untouched", which is the difference between a silent adopt and a notice.
    public var syncedPosition: ReadingPosition?

    public init(
        identity: PublicationIdentity,
        position: ReadingPosition,
        isFinished: Bool = false,
        finishedAt: Date? = nil,
        updatedAt: Date,
        syncedPosition: ReadingPosition? = nil
    ) {
        self.identity = identity
        self.position = position
        self.isFinished = isFinished
        self.finishedAt = finishedAt
        self.updatedAt = updatedAt
        self.syncedPosition = syncedPosition
    }

    /// The record this one becomes when the finished flag is set or cleared.
    ///
    /// The timestamp is the point: it is stamped when the flag turns on, *kept* while it
    /// stays on — so re-reading a finished publication does not restate when it was
    /// finished — and dropped when it turns off, because an unfinished publication has no
    /// completion to date.
    public func finished(_ finished: Bool, at moment: Date) -> ReadingProgress {
        var changed = self
        changed.isFinished = finished
        changed.finishedAt = finished ? (finishedAt ?? moment) : nil
        changed.updatedAt = moment
        return changed
    }
}

/// The outcome of merging a local record with a remote one.
public enum ProgressMergeOutcome: Sendable, Equatable {
    /// Remote adopted with no user-visible notice.
    case adoptRemote(ReadingProgress)
    /// Local kept; push it to the server.
    case keepLocalAndPush(ReadingProgress)
    /// Both moved since the last sync. The further position wins, and the user
    /// is told once — naming both — with the option to take the other.
    case conflict(resolved: ReadingProgress, discarded: ReadingPosition)
}

/// ADR-0006's conflict rules, in one place, so both platforms can be checked
/// against the same table.
///
/// | Situation | Result |
/// | --- | --- |
/// | Remote ahead, local untouched since last sync | adopt remote silently |
/// | Remote behind local | keep local, push |
/// | Both changed since last sync | further wins, tell the user once |
/// | One finished, one partial | finished wins |
public enum ProgressMerge {
    public static func merge(local: ReadingProgress, remote: ReadingProgress) -> ProgressMergeOutcome {
        // Finished is sticky. Unmarking a finished publication is a deliberate
        // act; losing it to a stale sync is never what someone wanted.
        if remote.isFinished && !local.isFinished {
            return .adoptRemote(remote)
        }
        if local.isFinished && !remote.isFinished {
            return .keepLocalAndPush(local)
        }

        let localMoved = local.syncedPosition.map { !$0.matches(local.position) } ?? true
        let remoteAhead = remote.position.fraction > local.position.fraction

        if !localMoved {
            // Nothing to lose locally: take whichever is further, quietly.
            return remoteAhead ? .adoptRemote(remote) : .keepLocalAndPush(local)
        }

        // Local moved since the last sync. Did remote move too?
        let remoteMoved = local.syncedPosition.map { !$0.matches(remote.position) } ?? true
        if !remoteMoved {
            return .keepLocalAndPush(local)
        }

        // Genuine conflict. Furthest wins — clock skew between a phone and a NAS
        // is real, and being a few pages ahead is recoverable in a way that
        // losing an evening's reading is not.
        if remoteAhead {
            return .conflict(resolved: remote, discarded: local.position)
        }
        if local.position.fraction > remote.position.fraction {
            return .conflict(resolved: local, discarded: remote.position)
        }
        // Identical positions are not a conflict at all.
        return .keepLocalAndPush(local)
    }
}
