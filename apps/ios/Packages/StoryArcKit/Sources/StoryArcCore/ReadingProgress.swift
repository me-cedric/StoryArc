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
}

public struct ReadingProgress: Sendable, Equatable, Codable {
    public let identity: PublicationIdentity
    public var position: ReadingPosition
    public var isFinished: Bool
    public var updatedAt: Date

    /// The last position successfully exchanged with the source. Comparing
    /// against it is how the merge tells "changed since last sync" from
    /// "untouched", which is the difference between a silent adopt and a notice.
    public var syncedPosition: ReadingPosition?

    public init(
        identity: PublicationIdentity,
        position: ReadingPosition,
        isFinished: Bool = false,
        updatedAt: Date,
        syncedPosition: ReadingPosition? = nil
    ) {
        self.identity = identity
        self.position = position
        self.isFinished = isFinished
        self.updatedAt = updatedAt
        self.syncedPosition = syncedPosition
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

        let localMoved = local.syncedPosition.map { $0 != local.position } ?? true
        let remoteAhead = remote.position.fraction > local.position.fraction

        if !localMoved {
            // Nothing to lose locally: take whichever is further, quietly.
            return remoteAhead ? .adoptRemote(remote) : .keepLocalAndPush(local)
        }

        // Local moved since the last sync. Did remote move too?
        let remoteMoved = local.syncedPosition.map { $0 != remote.position } ?? true
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
