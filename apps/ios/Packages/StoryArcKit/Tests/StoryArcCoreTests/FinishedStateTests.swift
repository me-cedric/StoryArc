import Foundation
import Testing

@testable import StoryArcCore

/// The completion timestamp, and the one rule that makes it worth having.
///
/// `reading-progress` asks for a publication to be "recorded finished with a completion
/// timestamp". The rule that carries the risk is not setting it — it is *not resetting*
/// it: reopening a finished publication writes a new position, and a timestamp that moved
/// with it would say the reader finished the book again every time they glanced at it.
///
/// Android's `FinishedStateTest` asserts the same table.
@Suite("Finished state")
struct FinishedStateTests {

    private let identity = PublicationIdentity(normalizedPath: "/comics/bone.cbz")
    private let first = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 9_000)

    private func partial() -> ReadingProgress {
        ReadingProgress(
            identity: identity,
            position: .page(index: 4, of: 20),
            updatedAt: first
        )
    }

    @Test("Finishing stamps the moment it was finished")
    func finishingStamps() {
        let done = partial().finished(true, at: first)

        #expect(done.isFinished)
        #expect(done.finishedAt == first)
    }

    @Test("Finishing again keeps the first completion")
    func finishingIsNotRestamped() {
        let done = partial().finished(true, at: first)
        let reread = done.finished(true, at: later)

        // The reader opened it again. They did not finish it again.
        #expect(reread.finishedAt == first)
        #expect(reread.updatedAt == later)
    }

    @Test("Unfinishing drops the completion, because there is no longer one to date")
    func unfinishingClears() {
        let reopened = partial().finished(true, at: first).finished(false, at: later)

        #expect(!reopened.isFinished)
        #expect(reopened.finishedAt == nil)
        #expect(reopened.updatedAt == later)
    }

    @Test("A publication nobody finished has no completion")
    func unfinishedHasNoStamp() {
        #expect(partial().finishedAt == nil)
    }
}
