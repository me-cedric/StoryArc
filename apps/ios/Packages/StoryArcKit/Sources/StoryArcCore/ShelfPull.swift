public import Foundation

/// The outcome of reconciling one server-backed shelf with the edits waiting for it.
public enum ShelfMergeOutcome: Sendable, Equatable {
    /// The server is where it was left. Send these, and say nothing.
    case push([ShelfEdit])
    /// The server already holds every edit that was waiting. Forget them, and say nothing —
    /// an edit that arrived is not a change worth a sentence.
    case settled([ShelfEdit])
    /// The server moved under a pending edit. Its version wins: `discarded` is what the
    /// reader loses and has to be told about, `settled` arrived before the change and is
    /// simply forgotten.
    case conflict(discarded: [ShelfEdit], settled: [ShelfEdit])
}

/// `collections-and-reading-lists`' two offline rules, in one place, so both platforms can
/// be checked against the same table.
///
/// | Situation | Result |
/// | --- | --- |
/// | Nothing waiting | settle nothing, say nothing |
/// | The server already holds everything that was waiting | settled, silently |
/// | The server holds what it held when the edit was made | push what is outstanding |
/// | The server moved under an outstanding edit | server wins, edit discarded, tell once |
/// | This shelf has never answered this device | push — losing the edit is what offline must never do |
///
/// The last row is the one that looks like a compromise and is not. Without a baseline
/// "did the server change" is unanswerable, and the two ways of guessing are not
/// symmetrical: pushing an addition the server already has changes nothing, while
/// discarding it loses work the reader can see they did.
///
/// Android's `ShelfMerge` decides the same five rows in the same order.
public enum ShelfMerge {

    public static func merge(
        baseline: [String]?,
        remote: [String],
        pending: [ShelfEdit]
    ) -> ShelfMergeOutcome {
        let held = Set(remote)
        let landed = pending.filter { held.contains($0.entry) }
        let waiting = pending.filter { !held.contains($0.entry) }

        // Nothing outstanding: whatever was queued, the server has it now. Covers an empty
        // queue, which is the ordinary case and must not raise a notice.
        if waiting.isEmpty { return .settled(landed) }

        guard let baseline else { return .push(waiting) }

        // Take our own arrivals back out before comparing. A list that differs from the
        // baseline only by an edit this device made is a list nobody else has touched.
        let ours = Set(landed.map(\.entry))
        let withoutOurs = remote.filter { !ours.contains($0) }
        if withoutOurs == baseline { return .push(waiting) }

        return .conflict(discarded: waiting, settled: landed)
    }

    /// What a reading list looks like while edits are still waiting for the server.
    ///
    /// The server's own entries first, in the server's order — it owns the order — and the
    /// outstanding ones after, oldest first, each marked. `collections-and-reading-lists`
    /// wants the edit "applied locally" *and* the pending state "visible on the list", and
    /// this is both at once: the entry is there, and it is visibly not there yet.
    public static func projecting(remote: [ShelfEntry], pending: [ShelfEdit]) -> [ShelfEntry] {
        let held = Set(remote.map(\.id))
        let waiting = pending
            .filter { !held.contains($0.entry) }
            .sorted { $0.madeAt < $1.madeAt }
        return remote + waiting.map {
            ShelfEntry(id: $0.entry, title: $0.title, isPending: true)
        }
    }
}

/// What one round of reconciling every server-backed shelf produced.
///
/// The same shape ``ProgressPull`` has, and for the same reason: a caller has to act
/// differently on each of the three, so they come back apart rather than as one list.
public struct ShelfPull: Sendable, Equatable {
    /// Edits to send now. The server is where it was left.
    public let toPush: [ShelfEdit]
    /// Edits nothing more is owed for — delivered, or discarded by a conflict.
    public let toDrop: [ShelfEdit]
    /// The conflicts worth a sentence, one per shelf, naming what was set aside.
    public let conflicts: [Conflict]

    public struct Conflict: Sendable, Equatable {
        public let shelf: ShelfKey
        public let discarded: [ShelfEdit]

        public init(shelf: ShelfKey, discarded: [ShelfEdit]) {
            self.shelf = shelf
            self.discarded = discarded
        }
    }

    public init(toPush: [ShelfEdit] = [], toDrop: [ShelfEdit] = [], conflicts: [Conflict] = []) {
        self.toPush = toPush
        self.toDrop = toDrop
        self.conflicts = conflicts
    }
}

public extension ShelfPull {

    /// Runs ``ShelfMerge`` across every shelf that answered this round.
    ///
    /// Pure, and takes both sides as values rather than reaching for a store, so the same
    /// table can be asserted on both platforms without a server or a device.
    ///
    /// A shelf that did not answer is absent from `remote` and is left entirely alone: its
    /// edits stay queued, its baseline stays as it was, and nobody is told anything. That is
    /// the unreachable server, and it is not a conflict.
    static func merging(
        remote: [ShelfSnapshot],
        baseline: (ShelfKey) -> [String]?,
        pending: [ShelfEdit]
    ) -> ShelfPull {
        var toPush: [ShelfEdit] = []
        var toDrop: [ShelfEdit] = []
        var conflicts: [Conflict] = []

        for snapshot in remote {
            let waiting = pending
                .filter { $0.shelf == snapshot.shelf }
                .sorted { $0.madeAt < $1.madeAt }
            switch ShelfMerge.merge(
                baseline: baseline(snapshot.shelf),
                remote: snapshot.entries,
                pending: waiting
            ) {
            case let .push(outstanding):
                toPush += outstanding
            case let .settled(landed):
                toDrop += landed
            case let .conflict(discarded, settled):
                toDrop += settled + discarded
                conflicts.append(Conflict(shelf: snapshot.shelf, discarded: discarded))
            }
        }

        return ShelfPull(toPush: toPush, toDrop: toDrop, conflicts: conflicts)
    }
}
