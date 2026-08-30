public import Foundation

/// What a source's detail screen says, and what it offers to do about it.
///
/// `sources` names five fields — "the state, the last successful sync, the last error in
/// plain language, the item count, and the bytes downloaded" — and five actions: test the
/// connection, refresh, clear the cache, remove downloads, remove the source. The settings
/// list carried two of the fields and one of the actions, so this is the answer to the
/// scenario rather than a tidier arrangement of what was already there.
///
/// A value computed from a source and the downloads it produced, not a screen. Which
/// actions a particular source can be offered is a decision with three inputs and no
/// pixels, and it was exactly the kind of decision the audit found untestable because it
/// lived in a view. Android's `SourceDiagnosis` answers the same five the same way.
public struct SourceDiagnosis: Sendable, Equatable {
    public let state: SourceConnectionState
    public let lastSuccessfulSync: Date?

    /// The last error, or nil when the source is not in one.
    ///
    /// Derived from the state rather than remembered beside it. A source that failed an
    /// hour ago and is answering now has no error a reader needs to read, and a field that
    /// kept one would be reporting the past as though it were the present — the same
    /// argument that keeps connection state off disk.
    public let failure: SourceFailure?

    /// How many publications the library holds from this source.
    public let itemCount: Int

    /// How many of them are downloaded, and what they weigh.
    ///
    /// Counted from the finished downloads alone: a queued one has no bytes on disk to
    /// free, so counting it would make "remove downloads" offer to free nothing.
    public let downloadCount: Int
    public let downloadedBytes: Int64

    /// In the order the screen shows them, destructive last.
    public let actions: [SourceAction]

    public init(
        state: SourceConnectionState,
        lastSuccessfulSync: Date?,
        failure: SourceFailure?,
        itemCount: Int,
        downloadCount: Int,
        downloadedBytes: Int64,
        actions: [SourceAction]
    ) {
        self.state = state
        self.lastSuccessfulSync = lastSuccessfulSync
        self.failure = failure
        self.itemCount = itemCount
        self.downloadCount = downloadCount
        self.downloadedBytes = downloadedBytes
        self.actions = actions
    }

    /// Everything the detail screen needs about one source.
    ///
    /// `isRemovable` is the caller's because the one source that cannot be removed is not a
    /// source the reader added — "On this device" is the app's own imported copies, and
    /// `local-library` deletes those one at a time, naming each.
    public static func of(
        _ source: Source,
        itemCount: Int,
        downloads: [Download],
        isRemovable: Bool = true
    ) -> SourceDiagnosis {
        let mine = downloads.filter { $0.sourceID == source.id && $0.state.isFinished }
        var actions: [SourceAction] = [.testConnection, .refresh, .clearCache]
        // Only when there is something to remove. An action that frees nothing still asks
        // for a confirmation, and a reader who answers it watches nothing happen.
        if !mine.isEmpty { actions.append(.removeDownloads) }
        if isRemovable { actions.append(.remove) }

        return SourceDiagnosis(
            state: source.state,
            lastSuccessfulSync: source.lastSuccessfulSync,
            failure: SourceFailure(source.state),
            itemCount: itemCount,
            downloadCount: mine.count,
            downloadedBytes: mine.reduce(0) { $0 + $1.downloadedBytes },
            actions: actions
        )
    }
}

/// Why a source is not answering, in the two ways it can fail.
///
/// The wording is presentation and lives in the feature that draws it; this is which
/// sentence to draw and what to put in it. Splitting the two is what lets the decision be
/// asserted without a bundle.
public enum SourceFailure: Sendable, Equatable {
    case unreachable(since: Date)
    case unauthorized(reason: String)

    /// Nil for a source that is connected or still connecting: neither is an error, and
    /// `sources` is explicit that offline "is a normal state, not an error".
    public init?(_ state: SourceConnectionState) {
        switch state {
        case .connected, .connecting: return nil
        case let .unreachable(since): self = .unreachable(since: since)
        case let .unauthorized(reason): self = .unauthorized(reason: reason)
        }
    }
}

/// What a source's detail screen can do to it.
public enum SourceAction: String, Sendable, Hashable, CaseIterable {
    /// Ask the source, now. For a folder that is whether it can still be read.
    case testConnection
    /// Re-fetch the catalogue.
    case refresh
    /// Drop the cached catalogue and covers. The downloads stay.
    case clearCache
    /// Delete the files this source produced. The source stays.
    case removeDownloads
    /// Remove the source, its cache, its secret and its downloads.
    case remove

    /// Whether the action needs a confirmation before it happens.
    ///
    /// Clearing a cache does not: it costs a refresh and nothing else. The other two
    /// delete bytes a reader may be relying on being there on a train.
    public var isDestructive: Bool {
        switch self {
        case .testConnection, .refresh, .clearCache: false
        case .removeDownloads, .remove: true
        }
    }
}
