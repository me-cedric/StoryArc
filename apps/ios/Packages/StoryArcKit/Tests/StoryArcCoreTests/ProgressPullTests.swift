import Foundation
import Testing

@testable import StoryArcCore

/// That the conflict rules are actually consulted, and that a pull says what to do next.
///
/// Mirrors Android's `ProgressPullTest`, assertion for assertion.
@Suite("Pulling progress")
struct ProgressPullTests {

    private func identity(_ id: String) -> PublicationIdentity {
        PublicationIdentity(contentDigest: id)
    }

    private func progress(
        _ id: String,
        at fraction: Double,
        finished: Bool = false,
        synced: Double? = nil
    ) -> ReadingProgress {
        var record = ReadingProgress(
            identity: identity(id),
            position: .reflowable(progression: fraction, locator: "{}"),
            isFinished: finished,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        record.syncedPosition = synced.map { .reflowable(progression: $0, locator: "{}") }
        return record
    }

    @Test("A publication the reader has never opened is taken as the server has it")
    func unknownPublicationIsAdopted() {
        let pull = ProgressPull.merging(remote: [progress("one", at: 0.4)]) { _ in nil }

        #expect(pull.toSave.count == 1)
        #expect(pull.toPush.isEmpty)
        #expect(pull.conflicts.isEmpty)
    }

    @Test("A server further ahead than an untouched local record is adopted quietly")
    func remoteAheadIsAdopted() {
        let held = progress("one", at: 0.2, synced: 0.2)
        let pull = ProgressPull.merging(remote: [progress("one", at: 0.6)]) { _ in held }

        #expect(pull.toSave.first?.position.fraction == 0.6)
        #expect(pull.conflicts.isEmpty)
    }

    @Test("A server behind the local record is pushed to, not adopted")
    func remoteBehindIsPushed() {
        let held = progress("one", at: 0.8, synced: 0.8)
        let pull = ProgressPull.merging(remote: [progress("one", at: 0.3)]) { _ in held }

        #expect(pull.toSave.isEmpty)
        #expect(pull.toPush.first?.position.fraction == 0.8)
    }

    @Test("Both moved since the last sync is a conflict, and the further one wins")
    func bothMovedIsAConflict() {
        // Last synced at 0.2; this device read on to 0.5, another to 0.9.
        let held = progress("one", at: 0.5, synced: 0.2)
        let pull = ProgressPull.merging(remote: [progress("one", at: 0.9)]) { _ in held }

        #expect(pull.conflicts.count == 1)
        #expect(pull.toSave.first?.position.fraction == 0.9)
        // What was set aside, so it can be offered back.
        #expect(pull.conflicts.first?.discarded.fraction == 0.5)
    }

    @Test("A publication finished anywhere stays finished")
    func finishedIsSticky() {
        let held = progress("one", at: 0.5, synced: 0.5)
        let pull = ProgressPull.merging(remote: [progress("one", at: 0.1, finished: true)]) { _ in held }

        #expect(pull.toSave.first?.isFinished == true)
    }

    @Test("A local record finished is pushed rather than being undone by the server")
    func localFinishedWins() {
        let held = progress("one", at: 1, finished: true, synced: 1)
        let pull = ProgressPull.merging(remote: [progress("one", at: 0.3)]) { _ in held }

        #expect(pull.toSave.isEmpty)
        #expect(pull.toPush.first?.isFinished == true)
    }

    @Test("A pull of many publications sorts each into the right pile")
    func manyAtOnce() {
        // Keyed on the identity's own `stableID`, which is what a store would key on —
        // the digest is one component of an identity and not the identity itself.
        let held = [
            progress("adopt", at: 0.1, synced: 0.1),
            progress("push", at: 0.9, synced: 0.9),
        ]
        let pull = ProgressPull.merging(
            remote: [progress("adopt", at: 0.5), progress("push", at: 0.2), progress("new", at: 0.3)]
        ) { wanted in held.first { $0.identity.stableID == wanted.stableID } }

        #expect(pull.toSave.count == 2)
        #expect(pull.toPush.count == 1)
    }

    @Test("Nothing reported is nothing to do")
    func emptyPull() {
        let pull = ProgressPull.merging(remote: []) { _ in nil }

        #expect(pull.toSave.isEmpty && pull.toPush.isEmpty && pull.conflicts.isEmpty)
    }
}
