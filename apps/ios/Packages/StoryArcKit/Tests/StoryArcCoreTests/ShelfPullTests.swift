import Foundation
import Testing

@testable import StoryArcCore

/// The two offline rules `collections-and-reading-lists` asks of a server-backed list:
/// an edit made while the server is away survives and is pushed, and an edit the server
/// has overtaken is discarded with one sentence about it.
///
/// Mirrors Android's `ShelfPullTest`, assertion for assertion.
@Suite("Reconciling a server-backed shelf")
struct ShelfPullTests {

    private let shelf = ShelfKey(sourceID: "server", shelfID: 7)

    private func edit(_ entry: String, at second: TimeInterval = 0) -> ShelfEdit {
        ShelfEdit(
            shelf: shelf,
            entry: entry,
            title: "Entry \(entry)",
            madeAt: Date(timeIntervalSince1970: second)
        )
    }

    // MARK: The table

    @Test("Nothing waiting settles nothing and says nothing")
    func emptyQueueIsQuiet() {
        let outcome = ShelfMerge.merge(baseline: ["a"], remote: ["a", "b"], pending: [])

        #expect(outcome == .settled([]))
    }

    @Test("A server that still holds what it held takes the outstanding edit")
    func unchangedServerIsPushedTo() {
        let queued = edit("b")
        let outcome = ShelfMerge.merge(baseline: ["a"], remote: ["a"], pending: [queued])

        #expect(outcome == .push([queued]))
    }

    @Test("An edit the server already has is settled, not announced")
    func landedEditIsSettled() {
        let queued = edit("b")
        let outcome = ShelfMerge.merge(baseline: ["a"], remote: ["a", "b"], pending: [queued])

        #expect(outcome == .settled([queued]))
    }

    @Test("A server that moved under an outstanding edit wins, and the edit is discarded")
    func movedServerWins() {
        let queued = edit("b")
        let outcome = ShelfMerge.merge(baseline: ["a"], remote: ["a", "c"], pending: [queued])

        #expect(outcome == .conflict(discarded: [queued], settled: []))
    }

    @Test("A reordered server is a conflict, because order is what a reading list is")
    func reorderedServerIsAConflict() {
        let queued = edit("c")
        let outcome = ShelfMerge.merge(
            baseline: ["a", "b"],
            remote: ["b", "a"],
            pending: [queued]
        )

        #expect(outcome == .conflict(discarded: [queued], settled: []))
    }

    @Test("An edit that arrived before the server moved is settled, not discarded")
    func landedEditSurvivesAConflict() {
        let landed = edit("b", at: 1)
        let waiting = edit("d", at: 2)
        let outcome = ShelfMerge.merge(
            baseline: ["a"],
            remote: ["a", "b", "c"],
            pending: [landed, waiting]
        )

        #expect(outcome == .conflict(discarded: [waiting], settled: [landed]))
    }

    @Test("A shelf never seen from this device is pushed to rather than second-guessed")
    func missingBaselineIsPushedTo() {
        let queued = edit("b")
        let outcome = ShelfMerge.merge(baseline: nil, remote: ["a", "c"], pending: [queued])

        #expect(outcome == .push([queued]))
    }

    // MARK: The projection

    @Test("A pending entry is on the list, after the server's own, and marked")
    func pendingEntryIsVisible() {
        let rows = ShelfMerge.projecting(
            remote: [ShelfEntry(id: "a", title: "First", isPending: false)],
            pending: [edit("b", at: 2), edit("c", at: 1)]
        )

        #expect(rows.map(\.id) == ["a", "c", "b"])
        #expect(rows.map(\.isPending) == [false, true, true])
    }

    @Test("An entry the server has already taken is not shown twice")
    func landedEntryIsNotDuplicated() {
        let rows = ShelfMerge.projecting(
            remote: [
                ShelfEntry(id: "a", title: "First", isPending: false),
                ShelfEntry(id: "b", title: "Second", isPending: false),
            ],
            pending: [edit("b")]
        )

        #expect(rows.map(\.id) == ["a", "b"])
        #expect(rows.allSatisfy { !$0.isPending })
    }

    // MARK: The pull

    @Test("A shelf that did not answer keeps its edits and raises nothing")
    func silentShelfIsLeftAlone() {
        let pull = ShelfPull.merging(
            remote: [],
            baseline: { _ in ["a"] },
            pending: [edit("b")]
        )

        #expect(pull.toPush.isEmpty)
        #expect(pull.toDrop.isEmpty)
        #expect(pull.conflicts.isEmpty)
    }

    @Test("Two shelves are decided apart, and only the one that moved is announced")
    func shelvesAreDecidedApart() {
        let other = ShelfKey(sourceID: "server", shelfID: 9)
        let quiet = edit("b")
        let clashing = ShelfEdit(
            shelf: other,
            entry: "z",
            title: "Entry z",
            madeAt: Date(timeIntervalSince1970: 0)
        )

        let pull = ShelfPull.merging(
            remote: [
                ShelfSnapshot(shelf: shelf, entries: ["a"]),
                ShelfSnapshot(shelf: other, entries: ["a", "c"]),
            ],
            baseline: { _ in ["a"] },
            pending: [quiet, clashing]
        )

        #expect(pull.toPush == [quiet])
        #expect(pull.toDrop == [clashing])
        #expect(pull.conflicts.count == 1)
        #expect(pull.conflicts.first?.shelf == other)
        #expect(pull.conflicts.first?.discarded == [clashing])
    }

    // MARK: The queue

    @Test("The same entry queued twice is one pending edit")
    func queueingIsIdempotent() {
        let queue = ShelfEditQueue()
            .queueing(edit("b", at: 1))
            .queueing(edit("b", at: 2))

        #expect(queue.edits.count == 1)
        #expect(queue.edits.first?.madeAt == Date(timeIntervalSince1970: 2))
    }

    @Test("A baseline replaces the shelf's earlier one rather than joining it")
    func baselineIsReplaced() {
        let queue = ShelfEditQueue()
            .recording(ShelfSnapshot(shelf: shelf, entries: ["a"]))
            .recording(ShelfSnapshot(shelf: shelf, entries: ["a", "b"]))

        #expect(queue.baselines.count == 1)
        #expect(queue.baseline(for: shelf) == ["a", "b"])
    }

    @Test("A notice is told once: acknowledging it leaves nothing to tell")
    func aNoticeIsToldOnce() throws {
        let notice = ShelfConflictNotice(
            shelf: shelf,
            shelfName: "Crossover",
            discarded: ["Entry b"],
            at: Date(timeIntervalSince1970: 5)
        )
        let queue = ShelfEditQueue().noting(notice)

        let first = try #require(queue.nextNotice)
        #expect(first.discarded == ["Entry b"])
        #expect(queue.acknowledging(first.id).nextNotice == nil)
    }

    @Test("A queue survives being written and read back")
    func queueRoundTrips() throws {
        let queue = ShelfEditQueue()
            .queueing(edit("b"))
            .recording(ShelfSnapshot(shelf: shelf, entries: ["a"]))
            .noting(
                ShelfConflictNotice(
                    shelf: shelf,
                    shelfName: "Crossover",
                    discarded: ["Entry c"],
                    at: Date(timeIntervalSince1970: 5)
                )
            )

        let data = try JSONEncoder().encode(queue)
        let read = try JSONDecoder().decode(ShelfEditQueue.self, from: data)

        #expect(read == queue)
    }

    @Test("A queue written before notices existed still reads")
    func partialQueueDecodes() throws {
        let data = Data(#"{"edits":[],"baselines":[]}"#.utf8)
        let read = try JSONDecoder().decode(ShelfEditQueue.self, from: data)

        #expect(read == ShelfEditQueue())
    }

    @Test("Removing a source forgets its edits, its baselines and its notices")
    func removingASourceForgetsEverything() {
        let queue = ShelfEditQueue()
            .queueing(edit("b"))
            .recording(ShelfSnapshot(shelf: shelf, entries: ["a"]))
            .noting(
                ShelfConflictNotice(
                    shelf: shelf,
                    shelfName: "Crossover",
                    discarded: ["Entry c"],
                    at: Date(timeIntervalSince1970: 5)
                )
            )

        #expect(queue.removingAll(from: "server") == ShelfEditQueue())
    }
}
