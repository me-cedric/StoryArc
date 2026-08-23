import Foundation
import Testing

@testable import StoryArcCore

/// The table in ADR-0006, asserted row by row. Android's `ProgressMergeTest`
/// asserts the same rows, which is how the two implementations stay honest
/// about the one rule a user would actually notice getting wrong.
@Suite("Progress merge follows ADR-0006")
struct ProgressMergeTests {
    private let identity = PublicationIdentity(contentDigest: "abc123")
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func progress(
        page: Int,
        of total: Int = 100,
        finished: Bool = false,
        synced: Int? = nil
    ) -> ReadingProgress {
        ReadingProgress(
            identity: identity,
            position: .page(index: page, of: total),
            isFinished: finished,
            updatedAt: epoch,
            syncedPosition: synced.map { .page(index: $0, of: total) }
        )
    }

    @Test("Remote ahead and local untouched adopts remote silently")
    func remoteAheadLocalUntouched() {
        let local = progress(page: 10, synced: 10)
        let remote = progress(page: 40)

        #expect(ProgressMerge.merge(local: local, remote: remote) == .adoptRemote(remote))
    }

    @Test("Remote behind local keeps local and pushes it")
    func remoteBehind() {
        let local = progress(page: 40, synced: 10)
        let remote = progress(page: 10)

        #expect(ProgressMerge.merge(local: local, remote: remote) == .keepLocalAndPush(local))
    }

    @Test("Both moved since last sync resolves to the further position and reports the conflict")
    func bothMoved() {
        let local = progress(page: 30, synced: 10)
        let remote = progress(page: 55)

        let outcome = ProgressMerge.merge(local: local, remote: remote)

        #expect(outcome == .conflict(resolved: remote, discarded: .page(index: 30, of: 100)))
    }

    @Test("A conflict where local is further keeps local and still reports it")
    func bothMovedLocalFurther() {
        let local = progress(page: 70, synced: 10)
        let remote = progress(page: 55)

        let outcome = ProgressMerge.merge(local: local, remote: remote)

        #expect(outcome == .conflict(resolved: local, discarded: .page(index: 55, of: 100)))
    }

    @Test("Finished wins over a further partial position")
    func finishedIsSticky() {
        // Remote is finished but sits at page 0; local is untouched at page 90.
        // Position alone would keep local. Finished must still win.
        let local = progress(page: 90, synced: 10)
        let remote = progress(page: 0, finished: true)

        #expect(ProgressMerge.merge(local: local, remote: remote) == .adoptRemote(remote))
    }

    @Test("A locally finished publication is never unmarked by a partial remote")
    func localFinishedSurvives() {
        let local = progress(page: 99, finished: true, synced: 10)
        let remote = progress(page: 5)

        #expect(ProgressMerge.merge(local: local, remote: remote) == .keepLocalAndPush(local))
    }

    @Test("Identical positions are not treated as a conflict")
    func identicalPositions() {
        let local = progress(page: 30, synced: 10)
        let remote = progress(page: 30)

        // Remote did not move relative to the last sync watermark comparison,
        // so there is nothing to reconcile and nothing to tell the user.
        #expect(ProgressMerge.merge(local: local, remote: remote) == .keepLocalAndPush(local))
    }

    @Test("A never-synced local record is treated as moved")
    func neverSynced() {
        let local = progress(page: 20, synced: nil)
        let remote = progress(page: 60)

        let outcome = ProgressMerge.merge(local: local, remote: remote)

        #expect(outcome == .conflict(resolved: remote, discarded: .page(index: 20, of: 100)))
    }
}

@Suite("Reading position normalises across kinds")
struct ReadingPositionTests {
    @Test("First page of a paged publication is zero and the last is one")
    func pagedBounds() {
        #expect(ReadingPosition.page(index: 0, of: 100).fraction == 0)
        #expect(ReadingPosition.page(index: 99, of: 100).fraction == 1)
    }

    @Test("A single-page publication does not divide by zero")
    func singlePage() {
        #expect(ReadingPosition.page(index: 0, of: 1).fraction == 1)
    }

    @Test("Reflowable progression is clamped to zero and one")
    func reflowableClamping() {
        #expect(ReadingPosition.reflowable(progression: -0.5, locator: "x").fraction == 0)
        #expect(ReadingPosition.reflowable(progression: 1.5, locator: "x").fraction == 1)
    }
}
