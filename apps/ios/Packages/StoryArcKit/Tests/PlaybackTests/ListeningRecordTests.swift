import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// What a session writes down, and what the app stores.
///
/// `reading-progress`: an audiobook's position "is an offset in time within a named part",
/// it "survives the app being closed, the device restarting, and the file being
/// re-downloaded", and reaching the end marks the publication finished "by the same rule
/// that marks a comic finished on its last page".
///
/// **The whole decision is here rather than in the app layer, and that is the point.** The
/// centre knows the parts, their durations and whether the source ran out; a closure in
/// `StoryArcApp` knows none of those and would have had to ask for them one at a time. So
/// ``PlayerCentre/onRecord`` hands over a finished ``ReachedListening`` and the app's only
/// job is to save it — which is the half a host test cannot reach.
@MainActor
@Suite("What a session records")
struct ListeningRecordTests {

    private func recorder(_ centre: PlayerCentre) -> Recorder {
        let recorder = Recorder()
        centre.onRecord = { reached in recorder.append(reached) }
        return recorder
    }

    /// Somewhere to put what a session wrote, since `onRecord` is a closure and a local
    /// `var` captured by one cannot be read back under strict concurrency.
    @MainActor
    final class Recorder {
        private(set) var reached: [ReachedListening] = []
        func append(_ one: ReachedListening) { reached.append(one) }
        var last: ReachedListening? { reached.last }
    }

    @Test("A narrated place is an offset in a part, with the part's own length beside it")
    func narratedCarriesItsLength() throws {
        let centre = PlayerCentre()
        let log = recorder(centre)
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: source)

        source.advance(toPart: 1, offset: 30)

        let reached = try #require(log.last)
        #expect(reached.position == .listening(part: 1, partCount: 3, offset: 30, of: 90))
        #expect(!reached.isFinished)
    }

    /// **No invented duration.** `design.md`: a synthesised voice does not know how long it
    /// will speak, and a position taken from one "has no total to divide by". A zero here
    /// would be a measurement nobody made.
    @Test("A spoken place carries no length at all")
    func spokenCarriesNone() throws {
        let centre = PlayerCentre()
        let log = recorder(centre)
        let source = PlaybackSourceDouble(.spoken)
        centre.begin(.stub(id: "a", title: "Sea Room"), source: source)

        source.advance(toPart: 2, offset: 0)

        let reached = try #require(log.last)
        #expect(reached.position == .listening(part: 2, partCount: 3, offset: 0, of: nil))
    }

    /// `reading-progress`: "the publication is marked finished by the same rule that marks a
    /// comic finished on its last page". A comic knows it is on its last page; an audiobook
    /// knows the source ran out, which is the same fact and the only exact one available —
    /// the clock ticks four times a second, so the last place a six-second fixture reports is
    /// nowhere near a fraction of 1.
    @Test("Running out marks the publication finished", arguments: SourceKind.allCases)
    func runningOutFinishes(_ kind: SourceKind) throws {
        let centre = PlayerCentre()
        let log = recorder(centre)
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: source)

        source.advance(toPart: 2, offset: 10)
        #expect(log.last?.isFinished == false, "not while there is more to play")

        source.runOut()
        #expect(try #require(log.last).isFinished, "the book ran out of words")
    }

    @Test("A listener stopping half way does not mark it finished")
    func stoppingDoesNotFinish() throws {
        let centre = PlayerCentre()
        let log = recorder(centre)
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: source)

        source.advance(toPart: 1, offset: 10)
        centre.end()

        #expect(try #require(log.last).isFinished == false)
    }

    /// A second session must not inherit the first's ending, or a listener who finished one
    /// book and started another would have the second marked finished at its first tick.
    @Test("A new book starts unfinished, however the last one ended")
    func endingDoesNotCarryOver() throws {
        let centre = PlayerCentre()
        let log = recorder(centre)

        let first = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: first)
        first.runOut()
        #expect(try #require(log.last).isFinished)

        let second = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "b", title: "Maus", format: .audiobook), source: second)
        second.advance(toPart: 1, offset: 5)

        let reached = try #require(log.last)
        #expect(reached.book.publication.displayTitle == "Maus")
        #expect(!reached.isFinished)
    }

    /// `audio-playback`: when a sleep timer elapses "the position at which it stopped is
    /// recorded, so resuming starts a little before it rather than where the fade ended". The
    /// rewind is `SleepCountdown.recordedPlace(afterFadingAt:)`; this asserts it reaches the
    /// *position*, which is the thing the store keeps.
    @Test("The sleep timer records a place before where the fade ended")
    func sleepTimerRewinds() throws {
        let centre = PlayerCentre()
        let log = recorder(centre)
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: source)

        source.advance(toPart: 0, offset: 40)
        centre.setSleepTimer(.after(60))
        centre.sleepTimerElapsed()

        #expect(
            try #require(log.last).position
                == .listening(part: 0, partCount: 3, offset: 40 - SleepCountdown.rewind, of: 120)
        )
    }
}
