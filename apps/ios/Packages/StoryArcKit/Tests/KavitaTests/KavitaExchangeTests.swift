import Foundation
import Testing

@testable import Kavita

import StoryArcCore

/// What a merge owes a Kavita server, and what a local record may then call synchronised.
///
/// Mirrors Android's `KavitaExchangeTest`, assertion for assertion.
@Suite("Exchanging progress with a Kavita server")
struct KavitaExchangeTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func progress(
        _ id: String,
        page: Int,
        of total: Int = 10,
        finished: Bool = false,
        synced: Int? = nil
    ) -> ReadingProgress {
        ReadingProgress(
            identity: PublicationIdentity(contentDigest: id),
            position: .page(index: page, of: total),
            isFinished: finished,
            updatedAt: epoch,
            syncedPosition: synced.map { .page(index: $0, of: total) }
        )
    }

    private func chapter(_ id: Int, pages: Int = 10) -> KavitaChapter {
        KavitaChapter(id: id, number: "1", title: "Chapter \(id)", pages: pages)
    }

    private func key(_ id: String) -> String {
        PublicationIdentity(contentDigest: id).stableID
    }

    // MARK: - The arithmetic

    @Test("A chapter read to its third page is a position on the third page")
    func pagesReadIsAPosition() {
        #expect(KavitaExchange.position(readingTo: 3, of: 8) == .page(index: 2, of: 8))
    }

    @Test("A chapter nobody has opened is a position at its beginning")
    func nothingReadIsPageZero() {
        #expect(KavitaExchange.position(readingTo: 0, of: 8) == .page(index: 0, of: 8))
    }

    @Test("A count past the end of the chapter is clamped rather than trusted")
    func pagesReadIsClamped() {
        #expect(KavitaExchange.position(readingTo: 99, of: 8) == .page(index: 7, of: 8))
    }

    @Test("A page position is told to the server as its own index")
    func pageIsItsOwnPageNumber() {
        #expect(KavitaExchange.pageNumber(of: .page(index: 4, of: 10), in: 10) == 4)
    }

    @Test("A reflowable position is told to the server by its fraction")
    func reflowableBecomesAPageNumber() {
        let halfway = ReadingPosition.reflowable(progression: 0.5, locator: "{}")

        #expect(KavitaExchange.pageNumber(of: halfway, in: 9) == 4)
    }

    @Test("A one-page chapter has one answer and no arithmetic")
    func singlePageChapter() {
        #expect(KavitaExchange.pageNumber(of: .page(index: 7, of: 1), in: 1) == 0)
    }

    @Test("A page index past the end is clamped rather than sent")
    func pageNumberIsClamped() {
        #expect(KavitaExchange.pageNumber(of: .page(index: 40, of: 10), in: 10) == 9)
    }

    // MARK: - The stamp

    @Test("A record the server has taken is stamped with the position it took")
    func settledCarriesTheStamp() {
        let stamped = KavitaExchange.settled(progress("one", page: 4))

        #expect(stamped.syncedPosition == .page(index: 4, of: 10))
    }

    // MARK: - The sorting

    @Test("A server behind the local record is owed that position, at the right page")
    func serverBehindIsOwed() {
        let held = progress("one", page: 8, synced: 8)
        let pull = ProgressPull.merging(remote: [progress("one", page: 2)]) { _ in held }

        let exchange = KavitaExchange.of(pull, against: [key("one"): chapter(41)])

        #expect(exchange.owed.count == 1)
        #expect(exchange.owed.first?.chapterId == 41)
        #expect(exchange.owed.first?.pageNum == 8)
    }

    @Test("A position the server has not taken yet is not called synchronised")
    func owedIsNotStampedUntilItLands() {
        let held = progress("one", page: 8, synced: 8)
        let pull = ProgressPull.merging(remote: [progress("one", page: 2)]) { _ in held }

        let exchange = KavitaExchange.of(pull, against: [key("one"): chapter(41)])

        // The stamp travels with the owed record, to be written once the send lands.
        #expect(exchange.toSave.isEmpty)
        #expect(exchange.owed.first?.settled.syncedPosition == .page(index: 8, of: 10))
    }

    @Test("A position adopted from the server is written with the stamp on it")
    func adoptedIsStamped() {
        let held = progress("one", page: 2, synced: 2)
        let pull = ProgressPull.merging(remote: [progress("one", page: 6)]) { _ in held }

        let exchange = KavitaExchange.of(pull, against: [key("one"): chapter(41)])

        #expect(exchange.owed.isEmpty)
        #expect(exchange.toSave.first?.syncedPosition == .page(index: 6, of: 10))
    }

    @Test("One sweep that finds the server both ahead and behind sorts each apart")
    func aheadAndBehindInOneSweep() {
        let held = [
            progress("adopt", page: 1, synced: 1),
            progress("push", page: 9, synced: 9),
        ]
        let pull = ProgressPull.merging(
            remote: [progress("adopt", page: 5), progress("push", page: 3)]
        ) { wanted in held.first { $0.identity.stableID == wanted.stableID } }

        let exchange = KavitaExchange.of(
            pull,
            against: [key("adopt"): chapter(41), key("push"): chapter(42)]
        )

        #expect(exchange.toSave.count == 1)
        #expect(exchange.toSave.first?.position == .page(index: 5, of: 10))
        #expect(exchange.owed.map(\.chapterId) == [42])
        #expect(exchange.owed.first?.pageNum == 9)
    }

    @Test("A conflict the local position wins is written now and owed to the server too")
    func localWinsAConflictAndIsStillPushed() {
        // Last synced at page 1; this device read on to 7, the server only to 4.
        let held = progress("one", page: 7, synced: 1)
        let pull = ProgressPull.merging(remote: [progress("one", page: 4)]) { _ in held }

        let exchange = KavitaExchange.of(pull, against: [key("one"): chapter(41)])

        #expect(pull.conflicts.count == 1)
        // Written as it stands, because the reader's place must survive an unreachable
        // server — and stamped only by the copy that goes out.
        #expect(exchange.toSave.first?.syncedPosition == .page(index: 1, of: 10))
        #expect(exchange.owed.first?.pageNum == 7)
    }

    @Test("A conflict the server wins is adopted and owed nothing")
    func serverWinsAConflict() {
        let held = progress("one", page: 3, synced: 1)
        let pull = ProgressPull.merging(remote: [progress("one", page: 8)]) { _ in held }

        let exchange = KavitaExchange.of(pull, against: [key("one"): chapter(41)])

        #expect(pull.conflicts.count == 1)
        #expect(exchange.owed.isEmpty)
        #expect(exchange.toSave.first?.syncedPosition == .page(index: 8, of: 10))
    }

    @Test("A record with no chapter behind it is left out rather than guessed at")
    func noChapterIsNotOwed() {
        let held = progress("one", page: 8, synced: 8)
        let pull = ProgressPull.merging(remote: [progress("one", page: 2)]) { _ in held }

        #expect(KavitaExchange.of(pull, against: [:]).owed.isEmpty)
    }

    @Test("A chapter the server reports no pages for is owed nothing")
    func pagelessChapterIsNotOwed() {
        let held = progress("one", page: 8, synced: 8)
        let pull = ProgressPull.merging(remote: [progress("one", page: 2)]) { _ in held }

        let exchange = KavitaExchange.of(pull, against: [key("one"): chapter(41, pages: 0)])

        #expect(exchange.owed.isEmpty)
    }

    @Test("Nothing merged is nothing to write and nothing to send")
    func emptyExchange() {
        let exchange = KavitaExchange.of(ProgressPull(), against: [:])

        #expect(exchange.toSave.isEmpty && exchange.owed.isEmpty)
    }
}
