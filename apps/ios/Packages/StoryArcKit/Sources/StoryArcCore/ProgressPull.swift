public import Foundation

/// What a pull did, so a caller can write it down and say what needs telling.
///
/// `reading-progress`: "progress recorded on other devices is merged into the local store",
/// and a genuine conflict is one the user "is told once — naming both — with the option to
/// take the other". Those are two different results and a caller has to act differently on
/// each, so a pull reports them apart rather than returning a list of records.
public struct ProgressPull: Sendable, Equatable {
    /// Records to write, whether they came from the server or were kept locally.
    public let toSave: [ReadingProgress]
    /// Records the server does not have, or has behind. `reading-progress` requires a
    /// failed push to be "queued and retried on the next successful connection".
    public let toPush: [ReadingProgress]
    /// The conflicts worth a sentence, with what was set aside so it can be offered back.
    public let conflicts: [Conflict]

    public struct Conflict: Sendable, Equatable {
        public let resolved: ReadingProgress
        public let discarded: ReadingPosition

        public init(resolved: ReadingProgress, discarded: ReadingPosition) {
            self.resolved = resolved
            self.discarded = discarded
        }
    }

    public init(
        toSave: [ReadingProgress] = [],
        toPush: [ReadingProgress] = [],
        conflicts: [Conflict] = []
    ) {
        self.toSave = toSave
        self.toPush = toPush
        self.conflicts = conflicts
    }
}

public extension ProgressPull {

    /// Merges what a source reports against what is held locally.
    ///
    /// The rules themselves are ``ProgressMerge``'s, and were written, tested and unreachable
    /// until this: nothing called them, so `reading-progress`'s whole synchronisation
    /// requirement rested on a table nobody consulted. This is the caller.
    ///
    /// Pure, and takes both sides as values rather than reaching for a store, so the same
    /// table can be asserted on both platforms without a server or a device.
    ///
    /// A publication the server has and the reader has never opened is adopted outright:
    /// there is nothing local to weigh it against, and refusing it would mean a reader who
    /// read a chapter on another device opens this one at page one.
    ///
    /// Android's `ProgressPull` merges the same way.
    static func merging(
        remote: [ReadingProgress],
        local: (PublicationIdentity) -> ReadingProgress?
    ) -> ProgressPull {
        var toSave: [ReadingProgress] = []
        var toPush: [ReadingProgress] = []
        var conflicts: [Conflict] = []

        for record in remote {
            guard let held = local(record.identity) else {
                toSave.append(record)
                continue
            }
            switch ProgressMerge.merge(local: held, remote: record) {
            case let .adoptRemote(adopted):
                toSave.append(adopted)
            case let .keepLocalAndPush(kept):
                toPush.append(kept)
            case let .conflict(resolved, discarded):
                toSave.append(resolved)
                conflicts.append(Conflict(resolved: resolved, discarded: discarded))
            }
        }

        return ProgressPull(toSave: toSave, toPush: toPush, conflicts: conflicts)
    }
}
