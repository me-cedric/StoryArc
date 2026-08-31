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

    /// Normalised 0…1, so two positions can be compared regardless of kind.
    public var fraction: Double {
        switch self {
        case let .page(index, total):
            guard total > 1 else { return total == 1 && index >= 0 ? 1 : 0 }
            return min(1, max(0, Double(index) / Double(total - 1)))
        case let .reflowable(progression, _):
            return min(1, max(0, progression))
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
