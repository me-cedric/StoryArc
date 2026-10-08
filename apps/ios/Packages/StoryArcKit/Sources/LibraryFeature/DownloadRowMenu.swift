public import StoryArcCore

/// One thing a reader can do to a transfer in the queue.
///
/// Task 24.3 of `close-the-audited-gaps`. A row carried up to four small buttons side by side
/// — two chevrons, *Pause* and *Stop* — each 28 pt tall and 8 pt from the next, so a finger hit
/// the wrong one. Two or more related actions are one menu (`design.md` §10), and what the menu
/// holds is decided here so a test can state it without a window.
public enum DownloadRowAction: Hashable, Sendable {
    case retry
    case resume
    case pause
    case moveEarlier
    case moveLater
    /// Takes a transfer still arriving out of the queue. The caller confirms.
    case stop
    /// Takes a transfer that already failed out of the queue. The caller confirms.
    case remove

    /// Whether the row is drawn as a destructive one, which is also whether it asks first.
    public var isDestructive: Bool { self == .stop || self == .remove }
}

/// What the queue's menus hold, in groups a separator divides.
public enum DownloadRowMenu {

    /// The rows for one transfer.
    ///
    /// The thing a reader came to do goes first — *Retry* on a failure, *Resume* on a hold,
    /// *Pause* on a transfer that is moving — and the removal is last, alone in its own group.
    /// Only a queued transfer has an order to change: a running one has started.
    public static func groups(for state: Download.State, canReorder: Bool) -> [[DownloadRowAction]] {
        switch state {
        case .failed: [[.retry], [.remove]]
        case .paused: [[.resume], [.remove]]
        case .queued, .running, .finished:
            [canReorder ? [.pause, .moveEarlier, .moveLater] : [.pause], [.stop]]
        }
    }
}

/// One thing a reader can do to every transfer at once.
public enum DownloadAllAction: Hashable, Sendable {
    case pauseAll
    case resumeAll
    /// Takes every transfer still pending out of the queue. The caller confirms.
    case cancelAll

    public var isDestructive: Bool { self == .cancelAll }

    /// Pausing and resuming are a pair; cancelling is the last row, in a group of its own.
    public static let groups: [[DownloadAllAction]] = [[.pauseAll, .resumeAll], [.cancelAll]]
}
