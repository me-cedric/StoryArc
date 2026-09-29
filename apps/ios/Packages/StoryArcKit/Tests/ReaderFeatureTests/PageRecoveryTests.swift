import Foundation
import Testing

import StoryArcCore
@testable import ReaderFeature

/// `ReaderModel.needsRecovery(currentIndex:pageCount:decoded:attempted:refused:)` — the rule
/// `watchForPageRecovery()` polls against, lifted so a test can hold it without a publication
/// to wait on.
///
/// `network-share`'s *Connection drops while reading*: "resume streaming at the current page"
/// after reconnecting. `warm(around:)`'s only other callers are `open`, `go(to:)` and
/// `noteMemoryPressure`, none of which fire on their own while the reader sits on one page —
/// so a page that failed stayed a spinner until a turn away and back asked for it again. This
/// is the condition that decides when the periodic retry should actually ask.
@MainActor
@Suite("Whether the page on screen still needs a read")
struct PageRecoveryTests {
    @Test("A page neither decoded, refused, nor in flight needs a read")
    func needsAReadWhenNothingElseExplainsItsAbsence() {
        #expect(
            ReaderModel.needsRecovery(
                currentIndex: 2, pageCount: 5, decoded: [], attempted: [], refused: []
            )
        )
    }

    @Test("An already-decoded page needs nothing")
    func decodedNeedsNothing() {
        #expect(
            !ReaderModel.needsRecovery(
                currentIndex: 2, pageCount: 5, decoded: [2], attempted: [], refused: []
            )
        )
    }

    @Test("A permanently refused page is not retried for ever")
    func refusedNeedsNothing() {
        #expect(
            !ReaderModel.needsRecovery(
                currentIndex: 2, pageCount: 5, decoded: [], attempted: [], refused: [2]
            )
        )
    }

    @Test("A read already in flight is not asked for twice")
    func inFlightNeedsNothing() {
        // `decode(_:)` inserts into `attempted` before it awaits, and only a failure
        // removes the entry — so this is the one state that distinguishes "still
        // reading" from "gave up and needs asking again".
        #expect(
            !ReaderModel.needsRecovery(
                currentIndex: 2, pageCount: 5, decoded: [], attempted: [2], refused: []
            )
        )
    }

    @Test("Only the current index is asked about, whatever else failed nearby")
    func onlyCurrentIndexMatters() {
        #expect(
            ReaderModel.needsRecovery(
                currentIndex: 2, pageCount: 5, decoded: [1, 3], attempted: [1, 3], refused: []
            )
        )
    }

    @Test("An index outside the publication needs nothing, rather than asking forever")
    func outOfRangeNeedsNothing() {
        #expect(!ReaderModel.needsRecovery(currentIndex: 9, pageCount: 5, decoded: [], attempted: [], refused: []))
    }
}

/// `ReaderModel.pageBlockedSince` — what `NetworkNotice` counts from.
///
/// The rule the timing defect turned on: a failure's own clock, once one exists, must win
/// over the plainer "still waiting on the first read" clock, and must keep running through
/// whatever `pageWaitStarted` does around later retries.
@MainActor
@Suite("What the reader counts the network notice from")
struct PageBlockedSinceTests {
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func model() -> ReaderModel {
        let location = Self.corpus.appending(path: "comics/natural-sort.cbz")
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: location.path),
            format: .cbz,
            displayTitle: "Natural Sort",
            origin: .inferred
        )
        return ReaderModel(publication: publication, url: location)
    }

    @Test("Neither set means no trouble")
    func neitherIsNil() {
        #expect(model().pageBlockedSince == nil)
    }

    @Test("Only waiting on the first read counts from that")
    func waitOnly() {
        let reader = model()
        let started = Date()
        reader.pageWaitStarted = started
        #expect(reader.pageBlockedSince == started)
    }

    @Test("A failure's own clock wins once one exists")
    func failingWinsOverWaiting() {
        let reader = model()
        reader.pageWaitStarted = Date()
        let failing = Date().addingTimeInterval(-90)
        reader.pageFailingSince = failing
        #expect(reader.pageBlockedSince == failing)
    }
}
