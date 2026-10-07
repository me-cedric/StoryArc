import Testing

@testable import Playback
import StoryArcCore

/// `collections-and-reading-lists` task 7.2: the end of an audiobook offers what comes next.
/// The offer has to know which book just finished after ``PlayerCentre/book`` has already
/// gone back to `nil` — that is what ``PlayerCentre/lastFinished`` is for. Android's
/// `PlayingBook.lastPlayed` answers the same need.
@MainActor
@Suite("The book kept past its own teardown")
struct PlayerLastFinishedTests {

    @Test("A book that runs out is kept as the last finished one")
    func runningOutIsKept() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)

        source.runOut()

        #expect(centre.book == nil)
        #expect(centre.lastFinished?.publication.displayTitle == "Sea Room")
    }

    @Test("The listener's own stop is not offered as finished")
    func listenerStopIsNotKept() {
        let centre = PlayerCentre()
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: PlaybackSourceDouble(.narrated))

        centre.end()

        #expect(centre.book == nil)
        #expect(centre.lastFinished == nil)
    }

    @Test("Starting a second book clears the first one's finished flag")
    func aSecondBookClearsTheFirst() {
        let centre = PlayerCentre()
        let first = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: first)
        first.runOut()
        #expect(centre.lastFinished?.publication.displayTitle == "Sea Room")

        centre.begin(.stub(id: "long-field", title: "The Long Field"), source: PlaybackSourceDouble(.narrated))

        #expect(centre.lastFinished == nil)
    }

    // MARK: - Task 2.5, owner answer O12

    /// A book whose last or only part fails ends the session, and the finished surface has to
    /// say how much was lost after ``PlayerCentre/unreadablePartCount`` is back to zero.
    @Test("What could not be played is kept past the teardown")
    func damageSurvivesTheEnd() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated, unreadableParts: 1)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)

        source.runOut()

        #expect(centre.unreadablePartCount == 0, "the live count goes with the session")
        #expect(centre.unreadableAtEnd == 1)
    }

    /// The count a part adds *during* playback is the one the source reports last, which is
    /// the count `truncated.m4b` produces: the file fails after the session began.
    @Test("A part that failed during playback is counted at the end")
    func damageDuringPlayback() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)

        source.unreadablePartCount = 2
        source.advance(toPart: 1, offset: 4)
        source.runOut()

        #expect(centre.unreadableAtEnd == 2)
    }

    @Test("A whole book states no loss")
    func wholeBookStatesNothing() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)

        source.runOut()

        #expect(centre.unreadableAtEnd == 0)
    }

    @Test("The listener's own stop leaves no finished surface to state anything")
    func stopStatesNothing() {
        let centre = PlayerCentre()
        centre.begin(
            .stub(id: "sea-room", title: "Sea Room", format: .m4b),
            source: PlaybackSourceDouble(.narrated, unreadableParts: 1)
        )

        centre.end()

        #expect(centre.unreadableAtEnd == 0)
    }

    @Test("A second book does not inherit the first one's loss")
    func lossIsNotInherited() {
        let centre = PlayerCentre()
        let first = PlaybackSourceDouble(.narrated, unreadableParts: 1)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: first)
        first.runOut()
        #expect(centre.unreadableAtEnd == 1)

        centre.begin(.stub(id: "long-field", title: "The Long Field"), source: PlaybackSourceDouble(.narrated))

        #expect(centre.unreadableAtEnd == 0)
    }
}
