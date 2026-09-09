import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// *When* a listening position is written, which is a different question from what it says.
///
/// `audio-playback`, *Where a listening position is written*: the moments are a pause, a jump
/// the listener chose, a part change, the app leaving the foreground and the end of a session,
/// with a floor of fifteen seconds of audio under all of them. `ListeningRecordTests` asserts
/// what a record carries; this suite asserts the moment one appears.
///
/// **Two defects, measured on 2026-09-08.** Nothing wrote on a pause, so a listener who paused
/// and then lost the process lost up to fifteen seconds of it. And every report
/// ``NarratedSource`` makes wrote a record — four a second, for the length of a book.
@MainActor
@Suite("When a listening position is written")
struct ListeningMomentTests {

    /// A narrated book playing, and somewhere to collect what it writes.
    private func started(_ log: Positions) -> (PlayerCentre, PlaybackSourceDouble) {
        let centre = PlayerCentre()
        centre.onRecord = { reached in log.append(reached.position) }
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .m4b), source: source)
        return (centre, source)
    }

    @Test("A pause writes where the listener stopped")
    func pauseWrites() {
        let log = Positions()
        let (centre, source) = started(log)
        source.advance(toPart: 0, offset: 8)
        let beforeThePause = log.all.count

        centre.pause()

        #expect(log.all.count == beforeThePause + 1, "a listener who pauses has decided to stop")
        #expect(log.last == .listening(part: 0, partCount: 3, offset: 8, of: 120))
    }

    /// The lock screen, a car and a paired watch send a pause; the app's own button toggles.
    /// Both are the listener deciding to stop, so both write.
    @Test("The toggle writes when it is the pause half of itself")
    func toggleWritesWhenItPauses() {
        let log = Positions()
        let (centre, source) = started(log)
        source.advance(toPart: 0, offset: 4)
        let beforeTheToggle = log.all.count

        centre.toggle()
        #expect(log.all.count == beforeTheToggle + 1)

        centre.toggle()
        #expect(log.all.count == beforeTheToggle + 1, "starting again is not a moment to write at")
    }

    /// **Inside the part already playing, which is the case the floor would swallow.** A move
    /// into a different part is written by ``crossingAPartWrites()``'s rule whoever caused it;
    /// a short move is written only because the listener chose it.
    @Test("A chapter chosen from the list writes at once, even a short move")
    func chosenChapterWrites() {
        let log = Positions()
        let (centre, source) = started(log)
        source.advance(toPart: 0, offset: 2)
        let beforeTheChoice = log.all.count

        centre.play(part: 0, offset: 9)

        #expect(log.all.count == beforeTheChoice + 1)
        #expect(log.last == .listening(part: 0, partCount: 3, offset: 9, of: 120))
    }

    @Test("A scrub writes where the listener dropped the handle")
    func scrubWrites() {
        let log = Positions()
        let (centre, source) = started(log)
        source.advance(toPart: 0, offset: 2)
        let beforeTheScrub = log.all.count

        centre.scrub(to: 9)

        #expect(log.all.count == beforeTheScrub + 1)
        #expect(log.last == .listening(part: 0, partCount: 3, offset: 9, of: 120))
    }

    /// The double does not move itself on a skip, which is the point: the write has to be the
    /// centre's own and not a report the engine happened to make.
    @Test("A skip writes, and does not wait for the engine to report")
    func skipWrites() {
        let log = Positions()
        let (centre, source) = started(log)
        source.advance(toPart: 1, offset: 30)
        let beforeTheSkip = log.all.count

        centre.skip(.forward)

        #expect(log.all.count == beforeTheSkip + 1)
    }

    /// **The floor.** Four reports a second is what ``NarratedSource`` makes, and a write on
    /// each of them is a store written four times a second for the length of a book.
    @Test("The clock alone writes at a floor rather than on every report")
    func theClockWritesAtAFloor() {
        let log = Positions()
        // The centre is named and read at the end: the source holds it weakly, so a test that
        // let go of it would be asserting over a session nothing is driving.
        let (centre, source) = started(log)

        source.advance(toPart: 0, offset: 0.25)
        #expect(log.all.count == 1, "the first report of a new book is always worth a write")

        for tick in 2...40 { source.advance(toPart: 0, offset: Double(tick) * 0.25) }
        #expect(log.all.count == 1, "ten seconds of audio is under the floor")

        source.advance(toPart: 0, offset: 15.25)
        #expect(log.all.count == 2, "and past the floor one write appears")
        #expect(centre.time.elapsed == 15.25, "the session followed the clock all along")
    }

    /// Crossing a chapter is a landmark, and the offset restarts at it — so the floor cannot
    /// be what decides. A listener who crosses into chapter two and loses the process there
    /// must not come back to chapter one.
    @Test("Crossing a part writes, however little audio has passed")
    func crossingAPartWrites() {
        let log = Positions()
        let (centre, source) = started(log)
        source.advance(toPart: 0, offset: 1)
        let beforeTheCrossing = log.all.count

        source.advance(toPart: 1, offset: 0)

        #expect(log.all.count == beforeTheCrossing + 1)
        #expect(log.last == .listening(part: 1, partCount: 3, offset: 0, of: 90))
        #expect(centre.currentPart?.title == "Two", "the session crossed with it")
    }

    /// A second book starts its own floor. Inheriting the first's would leave the opening
    /// minutes of the second unwritten, until its offset climbed past where the first stopped.
    @Test("A new book writes its first report, whatever the last book reached")
    func aNewBookStartsItsOwnFloor() {
        let log = Positions()
        let (centre, first) = started(log)
        first.advance(toPart: 0, offset: 55)

        let second = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "b", title: "Maus", format: .m4b), source: second)
        let beforeTheSecondPlayed = log.all.count
        second.advance(toPart: 0, offset: 1)

        #expect(log.all.count == beforeTheSecondPlayed + 1)
        #expect(log.last == .listening(part: 0, partCount: 3, offset: 1, of: 120))
    }
}
