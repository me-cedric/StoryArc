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
}
