import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// `close-the-audited-gaps` 23.6, owner answer O21: a damaged ending is not recorded as
/// finished. The position stays at the failed part, the finished surface states the loss (O12),
/// and the listener decides whether the book counts as finished.
@MainActor
@Suite("A book that ends on a failed part")
struct PlayerDamagedEndingTests {

    @MainActor final class Records { var all: [ReachedListening] = [] }

    private func listening(
        _ centre: PlayerCentre,
        source: PlaybackSourceDouble = PlaybackSourceDouble(.narrated, unreadableParts: 1)
    ) -> (source: PlaybackSourceDouble, records: Records) {
        let records = Records()
        centre.onRecord = { records.all.append($0) }
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)
        return (source, records)
    }

    @Test("Its record is not finished, and holds the part that failed")
    func theRecordIsNotFinished() {
        let centre = PlayerCentre()
        let (source, records) = listening(centre)
        source.advance(toPart: 2, offset: 31)

        source.runOutOnFailure()

        let last = records.all.last
        #expect(last?.isFinished == false, "a damaged ending was recorded as a finished book")
        #expect(last?.position == .listening(part: 2, partCount: 3, offset: 31, of: 60))
    }

    @Test("A book that plays to its end is still recorded as finished")
    func aWholeEndingIsFinished() {
        let centre = PlayerCentre()
        let (source, records) = listening(centre, source: PlaybackSourceDouble(.narrated))

        source.runOut()

        #expect(records.all.last?.isFinished == true)
        #expect(centre.endedOnFailure == false)
        #expect(centre.canMarkFinished == false, "there is nothing to decide about a whole book")
    }

    @Test("The surface still states the ending, and offers Mark as finished")
    func theSurfaceOffersTheDecision() {
        let centre = PlayerCentre()
        let (source, _) = listening(centre)

        source.runOutOnFailure()

        #expect(centre.hasReachedTheEnd, "the finished surface is the one that draws")
        #expect(centre.endedOnFailure)
        #expect(centre.canMarkFinished)
        #expect(centre.unreadableAtEnd == 1)
        #expect(centre.lastFinished?.publication.displayTitle == "Sea Room")
    }

    @Test("Marking it finished writes one finished record at the failed part")
    func markingWritesOnce() {
        let centre = PlayerCentre()
        let (source, records) = listening(centre)
        source.advance(toPart: 1, offset: 12)
        source.runOutOnFailure()
        let before = records.all.count

        centre.markFinished()
        centre.markFinished()

        #expect(records.all.count == before + 1, "marked twice, or not at all")
        #expect(records.all.last?.isFinished == true)
        #expect(records.all.last?.position == .listening(part: 1, partCount: 3, offset: 12, of: 90))
        #expect(centre.canMarkFinished == false)
        #expect(centre.markedFinishedByHand)
    }

    @Test("The listener's own stop offers nothing to mark")
    func aStopOffersNothing() {
        let centre = PlayerCentre()
        let (_, records) = listening(centre)

        centre.end()
        centre.markFinished()

        #expect(centre.canMarkFinished == false)
        #expect(records.all.allSatisfy { !$0.isFinished })
    }

    @Test("A second book does not inherit the first one's offer")
    func theOfferIsNotInherited() {
        let centre = PlayerCentre()
        let (source, _) = listening(centre)
        source.runOutOnFailure()
        #expect(centre.canMarkFinished)

        centre.begin(.stub(id: "long-field", title: "The Long Field"), source: PlaybackSourceDouble(.narrated))

        #expect(centre.canMarkFinished == false)
        #expect(centre.endedOnFailure == false)
    }
}
